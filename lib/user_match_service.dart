import 'package:supabase_flutter/supabase_flutter.dart';

import 'match_utils.dart';
import 'user_profile_completion.dart';

/// One card in dashboard carousels — aligned with web profile carousel rows.
class MatchPreview {
  const MatchPreview({
    required this.userId,
    required this.name,
    this.age,
    required this.location,
    this.photoUrl,
    this.isPremium = false,
  });

  final String userId;
  final String name;
  final int? age;
  final String location;
  final String? photoUrl;
  final bool isPremium;
}

class UserMatchSets {
  const UserMatchSets({
    required this.daily,
    required this.allMatches,
    required this.newMatches,
  });

  final List<MatchPreview> daily;
  final List<MatchPreview> allMatches;
  final List<MatchPreview> newMatches;
}

/// Loads “Daily recommendations”, “All matches”, and “New members” the same way as
/// [manavizha/components/user-landing-page.tsx] (seeded daily shuffle + preference filters).
Future<UserMatchSets> loadUserMatchSections(SupabaseClient client, String userId) async {
  final userRow = await client.from('personal_details').select('sex').eq('user_id', userId).maybeSingle();
  if (userRow == null) {
    return const UserMatchSets(daily: [], allMatches: [], newMatches: []);
  }
  final sex = (userRow['sex'] as String? ?? '').toLowerCase();
  final targetGender = sex.contains('male') && !sex.contains('female') ? 'Female' : 'Male';

  final prefs = await client.from('partner_preferences').select('min_age, max_age').eq('user_id', userId).maybeSingle();
  final minAge = prefs != null ? prefs['min_age'] as int? : null;
  final maxAge = prefs != null ? prefs['max_age'] as int? : null;

  final potential = await client
      .from('personal_details')
      .select('user_id, name, age, sex, marital_status, created_at')
      .ilike('sex', targetGender)
      .neq('user_id', userId)
      .neq('marital_status', 'Married')
      .limit(150);

  final rows = (potential as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (rows.isEmpty) {
    return const UserMatchSets(daily: [], allMatches: [], newMatches: []);
  }

  var filtered = rows;
  if (minAge != null) {
    filtered = filtered.where((p) => p['age'] == null || (p['age'] as num) >= minAge).toList();
  }
  if (maxAge != null) {
    filtered = filtered.where((p) => p['age'] == null || (p['age'] as num) <= maxAge).toList();
  }

  final ids = filtered.map((p) => p['user_id'].toString()).toList();
  final photosRes = await client.from('photos').select('user_id, user_photos').inFilter('user_id', ids);
  final contactRes = await client.from('contact_details').select('user_id, current_district, current_state').inFilter('user_id', ids);
  final settingsRes = await client.from('user_settings').select('user_id, is_premium').inFilter('user_id', ids);

  final photoRows = (photosRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final contactRows = (contactRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final settingsRows = (settingsRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<MatchPreview> buildPreview(Map<String, dynamic> p) async {
    final id = p['user_id'].toString();
    Map<String, dynamic>? ph;
    for (final r in photoRows) {
      if (r['user_id']?.toString() == id) {
        ph = r;
        break;
      }
    }
    final photos = ph != null ? (ph['user_photos'] as List<dynamic>? ?? []) : <dynamic>[];
    String? url;
    for (final raw in photos) {
      final u = await signUserProfilePhoto(client, id, raw.toString());
      if (u != null && u.isNotEmpty) {
        url = u;
        break;
      }
    }
    Map<String, dynamic>? c;
    for (final r in contactRows) {
      if (r['user_id']?.toString() == id) {
        c = r;
        break;
      }
    }
    final d = c != null ? c['current_district']?.toString() : null;
    final s = c != null ? c['current_state']?.toString() : null;
    var loc = '—';
    if (d != null && d.isNotEmpty) {
      loc = s != null && s.isNotEmpty ? '$d, $s' : d;
    } else if (s != null && s.isNotEmpty) {
      loc = s;
    }

    var premium = false;
    for (final r in settingsRows) {
      if (r['user_id']?.toString() == id) {
        premium = r['is_premium'] == true;
        break;
      }
    }

    return MatchPreview(
      userId: id,
      name: p['name']?.toString().trim().isNotEmpty == true ? p['name'].toString() : 'Member',
      age: p['age'] != null ? (p['age'] as num).round() : null,
      location: loc,
      photoUrl: url,
      isPremium: premium,
    );
  }

  final previews = await Future.wait(filtered.map(buildPreview));

  final seedStr = getDailySeed(userId);
  final shuffled = seededShuffle(previews, seedStr);

  final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
  final fresh = previews.where((pr) {
    final row = filtered.firstWhere(
      (x) => x['user_id'].toString() == pr.userId,
      orElse: () => <String, dynamic>{},
    );
    if (row.isEmpty) return false;
    final ca = row['created_at']?.toString();
    if (ca == null) return false;
    return DateTime.tryParse(ca)?.isAfter(thirtyDaysAgo) ?? false;
  }).toList();

  return UserMatchSets(
    daily: shuffled.take(10).toList(),
    allMatches: previews,
    newMatches: fresh,
  );
}
