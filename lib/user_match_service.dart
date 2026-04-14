import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'match_utils.dart';
import 'user_profile_completion.dart';

/// [interests.hobbies] / [interests.interests] — PostgREST may return json arrays, PG `text[]`, or stringified JSON.
List<String> parseInterestsTableArrayColumn(dynamic v) {
  if (v == null) return [];
  if (v is List) {
    final out = <String>[];
    for (final e in v) {
      final s = e?.toString().trim() ?? '';
      if (s.isNotEmpty && s != 'null') out.add(s);
    }
    return out;
  }
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty || t == 'null') return [];
    if (t.startsWith('[')) {
      try {
        final decoded = jsonDecode(t);
        return parseInterestsTableArrayColumn(decoded);
      } catch (_) {}
    }
    if (t.startsWith('{') && t.endsWith('}')) {
      final inner = t.substring(1, t.length - 1).trim();
      if (inner.isEmpty) return [];
      return inner
          .split(',')
          .map((s) => s.trim().replaceAll('"', '').replaceAll("'", ''))
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  if (v is Map) {
    for (final val in v.values) {
      if (val is List || val is String) {
        final parsed = parseInterestsTableArrayColumn(val);
        if (parsed.isNotEmpty) return parsed;
      }
    }
  }
  return [];
}

/// One card in dashboard carousels — aligned with web profile carousel rows.
class MatchPreview {
  const MatchPreview({
    required this.userId,
    required this.name,
    this.age,
    required this.location,
    this.photoUrl,
    this.isPremium = false,
    this.educationDegree,
    this.jobTitle,
    List<String>? interestTags,
  }) : _interestTags = interestTags;

  final String userId;
  final String name;
  final int? age;
  final String location;

  /// First entry in [photos.user_photos] only (daily cards never show the rest here).
  final String? photoUrl;
  final bool isPremium;

  /// Latest education row’s [education] text (batch: last row per user in query order).
  final String? educationDegree;

  /// One-line current role (employee designation/company, business, or student), aligned with [MemberProfileViewScreen].
  final String? jobTitle;

  final List<String>? _interestTags;

  /// `interests` column from [interests] table (chips on daily cards). Getter tolerates null after hot reload.
  List<String> get interestTags => _interestTags ?? const [];
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
  final eduRes = await client.from('education_details').select('user_id, education').inFilter('user_id', ids);
  final empRes = await client.from('profession_employee').select('user_id, designation, company').inFilter('user_id', ids);
  final busRes = await client.from('profession_business').select('user_id, designation, business_name').inFilter('user_id', ids);
  final stuRes = await client.from('profession_student').select('user_id, course, institution').inFilter('user_id', ids);
  final interestsRes = await client.from('interests').select('user_id, interests').inFilter('user_id', ids);

  final photoRows = (photosRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final contactRows = (contactRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final settingsRows = (settingsRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final eduRows = (eduRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final empRows = (empRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final busRows = (busRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final stuRows = (stuRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final interestRows = (interestsRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  bool sameUserId(dynamic a, String uid) =>
      a != null && a.toString().trim().toLowerCase() == uid.trim().toLowerCase();

  List<String> interestsListForUser(String uid) {
    for (final r in interestRows) {
      if (sameUserId(r['user_id'], uid)) {
        return parseInterestsTableArrayColumn(r['interests']);
      }
    }
    return [];
  }

  final Map<String, List<String>> eduByUser = {};
  for (final row in eduRows) {
    final uid = row['user_id']?.toString();
    final ed = row['education']?.toString().trim() ?? '';
    if (uid == null || ed.isEmpty) continue;
    eduByUser.putIfAbsent(uid, () => []).add(ed);
  }

  String? lastEducationFor(String uid) {
    final list = eduByUser[uid];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  Map<String, dynamic>? firstRowFor(String uid, List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (r['user_id']?.toString() == uid) return r;
    }
    return null;
  }

  /// Short label for cards: job title / role (designation preferred over company name).
  String? jobLineFor(String uid) {
    final emp = firstRowFor(uid, empRows);
    if (emp != null) {
      final des = emp['designation']?.toString().trim() ?? '';
      final comp = emp['company']?.toString().trim() ?? '';
      if (des.isNotEmpty) return des;
      if (comp.isNotEmpty) return comp;
      return null;
    }
    final bus = firstRowFor(uid, busRows);
    if (bus != null) {
      final des = bus['designation']?.toString().trim() ?? '';
      final bn = bus['business_name']?.toString().trim() ?? '';
      if (des.isNotEmpty) return des;
      if (bn.isNotEmpty) return bn;
      return null;
    }
    final stu = firstRowFor(uid, stuRows);
    if (stu != null) {
      final co = stu['course']?.toString().trim() ?? '';
      final ins = stu['institution']?.toString().trim() ?? '';
      if (co.isNotEmpty) return co;
      if (ins.isNotEmpty) return ins;
      return null;
    }
    return null;
  }

  Future<MatchPreview> buildPreview(Map<String, dynamic> p) async {
    final id = p['user_id'].toString();
    Map<String, dynamic>? ph;
    for (final r in photoRows) {
      if (r['user_id']?.toString() == id) {
        ph = r;
        break;
      }
    }
    final photos = ph != null ? parseUserPhotosList(ph['user_photos']) : <dynamic>[];
    // Daily card: first resolvable gallery image (same order as [photos.user_photos]).
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
      educationDegree: lastEducationFor(id),
      jobTitle: jobLineFor(id),
      interestTags: interestsListForUser(id),
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
