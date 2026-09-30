import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads of *other* members' data go through the `public_*` views added by the
/// web app's migrations (`web app/migrations/2026-09-30_security_hardening.sql`
/// and `2026-10-01_privacy_and_identity.sql`). Once those run, the underlying
/// tables are readable only by the owner, their parent login, or an admin.
///
/// Until a view exists on the connected database, reads fall back to the
/// legacy table (mirrors the web's `lib/public-views.ts` shim, but detected at
/// runtime so the same build works before and after the migrations).
///
/// Usage — call [ensure] before building queries, then use [from]:
/// ```dart
/// await PublicViews.ensure(client, [PublicViews.users]);
/// final rows = await PublicViews.from(client, PublicViews.users, 'id, name').inFilter('id', ids);
/// ```
class PublicViews {
  PublicViews._();

  static const personalDetails = 'public_personal_details';
  static const familyDetails = 'public_family_details';
  static const horoscopeDetails = 'public_horoscope_details';
  static const profilePhotos = 'public_profile_photos';
  static const contactLocations = 'public_contact_locations';
  static const users = 'public_users';
  static const memberStatus = 'public_member_status';

  static const all = [
    personalDetails,
    familyDetails,
    horoscopeDetails,
    profilePhotos,
    contactLocations,
    users,
    memberStatus,
  ];

  /// Legacy table per view, columns the table lacks, and extra columns the
  /// legacy path needs so callers can compute what the view precomputes.
  static const Map<String, ({String table, List<String> missing, List<String> extra})> _legacy = {
    profilePhotos: (table: 'photos', missing: ['photos_locked', 'photo_count'], extra: []),
    contactLocations: (table: 'contact_details', missing: [], extra: []),
    users: (table: 'users', missing: [], extra: []),
    memberStatus: (table: 'user_settings', missing: [], extra: ['premium_expires_at', 'deactivated_until']),
    personalDetails: (table: 'personal_details', missing: [], extra: []),
    familyDetails: (table: 'family_details', missing: [], extra: []),
    horoscopeDetails: (table: 'horoscope_details', missing: ['details_locked'], extra: []),
  };

  static final Map<String, bool> _available = {};
  static final Map<String, Future<void>> _probes = {};

  /// Probes (once per session) whether each view exists. Safe to call often.
  static Future<void> ensure(SupabaseClient client, [List<String> views = all]) {
    return Future.wait(views.map((v) => _probes[v] ??= _probe(client, v)));
  }

  static Future<void> _probe(SupabaseClient client, String view) async {
    try {
      await client.from(view).select().limit(1);
      _available[view] = true;
    } on PostgrestException catch (e) {
      // PGRST205 / 42P01: relation not found → migration not applied yet.
      final missing = e.code == 'PGRST205' || e.code == '42P01' || e.message.contains('does not exist');
      if (missing) {
        _available[view] = false;
        if (kDebugMode) debugPrint('PublicViews: $view missing, using legacy table');
      } else {
        _probes.remove(view); // transient — retry next time
      }
    } catch (_) {
      _probes.remove(view);
    }
  }

  /// True when [view] is known to exist (false while unprobed or missing).
  static bool isLive(String view) => _available[view] == true;

  /// `client.from(view).select(columns)`, or the legacy table when the view is
  /// missing. Call [ensure] first; unprobed views are treated as live.
  static PostgrestFilterBuilder<List<Map<String, dynamic>>> from(
    SupabaseClient client,
    String view, [
    String columns = '*',
  ]) {
    final legacy = _legacy[view];
    if (legacy == null || _available[view] != false) {
      return client.from(view).select(columns);
    }
    return client.from(legacy.table).select(_legacyColumns(columns, legacy.missing, legacy.extra));
  }

  static String _legacyColumns(String columns, List<String> missing, List<String> extra) {
    if (columns.trim() == '*') return '*';
    final cols = columns
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty && !missing.contains(c))
        .toList();
    for (final e in extra) {
      if (!cols.contains(e)) cols.add(e);
    }
    return cols.join(', ');
  }
}

/// Whether a `public_member_status` (or legacy `user_settings`) row is an
/// active deactivation. The view precomputes this; the legacy row needs the
/// `deactivated_until` check.
bool isDeactivationActive(Map<String, dynamic>? row) {
  if (row == null || row['is_deactivated'] != true) return false;
  final until = DateTime.tryParse(row['deactivated_until']?.toString() ?? '');
  return until == null || until.isAfter(DateTime.now());
}
