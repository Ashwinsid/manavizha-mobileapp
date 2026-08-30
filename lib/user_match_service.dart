import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'astrology.dart';
import 'profile_scoring.dart';

import 'match_utils.dart';
import 'user_activity_tracker.dart';
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
    this.lastActiveAt,
    this.createdAt,
    this.star,
    this.zodiacSign,
    this.maritalStatus,
    this.caste,
    this.subcaste,
    this.educationLevels = const [],
    this.photoVerified = false,
    this.profileCode,
    this.poruthamScore,
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

  /// Latest heartbeat from the `users` table (UTC). Drives the green online
  /// dot + "Active X ago" chip — same source the web cards read from.
  final DateTime? lastActiveAt;

  /// `personal_details.created_at` — populated by [loadUserMatchSections] and
  /// used by the Browse "New members" filter (last 30 days).
  final DateTime? createdAt;

  /// Optional birth star and rashi from `horoscope_details`. Populated by
  /// [loadUserMatchSections]; used by the Browse Star / Horoscope category
  /// filters and by the porutham score.
  final String? star;
  final String? zodiacSign;

  /// Manual Browse-filter fields (web `BrowseManualFilters` parity). Only
  /// populated by [loadUserMatchSections]; empty/false elsewhere.
  final String? maritalStatus;
  final String? caste;
  final String? subcaste;

  /// Computed 10-Porutham score against the signed-in user (0-10).
  final int? poruthamScore;

  /// All `education_details.education` values for the member.
  final List<String> educationLevels;

  /// `photos.photo_verified` — drives the "Verified profile" filter.
  final bool photoVerified;

  final String? profileCode;
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
///
/// When [applyPreferences] is `false`, age preferences from
/// `partner_preferences` are ignored. This mirrors the
/// "Apply preferences" toggle on the web Browse Profiles page so it can
/// expand the dataset on demand.
Future<UserMatchSets> loadUserMatchSections(
  SupabaseClient client,
  String userId, {
  bool applyPreferences = true,
}) async {
  final userRow = await client.from('personal_details').select('sex').eq('user_id', userId).maybeSingle();
  if (userRow == null) {
    return const UserMatchSets(daily: [], allMatches: [], newMatches: []);
  }
  final sex = (userRow['sex'] as String? ?? '').toLowerCase();
  final targetGender = sex.contains('male') && !sex.contains('female') ? 'Female' : 'Male';

  final myHoro = await client.from('horoscope_details').select('star, zodiac_sign').eq('user_id', userId).maybeSingle();

  final prefs = await client.from('partner_preferences').select().eq('user_id', userId).maybeSingle();
  final minAge = prefs != null ? prefs['preferred_age_min'] as int? : null;
  final maxAge = prefs != null ? prefs['preferred_age_max'] as int? : null;
  final prefCasteStr = prefs != null ? prefs['preferred_caste']?.toString() : null;
  final casteCompulsory = prefs != null && prefs['caste_compulsory'] == true;
  final prefCasteArr = prefCasteStr != null && prefCasteStr.isNotEmpty ? prefCasteStr.split(', ') : <String>[];

  // No explicit cap — matches the web Browse query, which fetches every
  // matching profile (both are bounded only by PostgREST's server-side
  // max-rows setting).
  final potential = await client
      .from('personal_details')
      .select('user_id, name, age, sex, marital_status, created_at, photo_verified, profile_code')
      .ilike('sex', targetGender)
      .neq('user_id', userId)
      .neq('marital_status', 'Married')
      .neq('is_hidden', true);

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
  final contactRes = await client.from('contact_details').select('user_id, current_country, current_state, current_district').inFilter('user_id', ids);
  final settingsRes = await client.from('user_settings').select('user_id, is_premium').inFilter('user_id', ids);
  final eduRes = await client.from('education_details').select('user_id, education, degree, branch').inFilter('user_id', ids);
  final empRes = await client.from('profession_employee').select('user_id, designation, company, employment_type, salary').inFilter('user_id', ids);
  final busRes = await client.from('profession_business').select('user_id, designation, business_name, business_type, annual_returns').inFilter('user_id', ids);
  final stuRes = await client.from('profession_student').select('user_id, course, institution').inFilter('user_id', ids);
  final interestsRes = await client.from('interests').select('user_id, interests').inFilter('user_id', ids);
  // Tolerant fetch: `users` may be RLS-restricted on some deployments. If the
  // request fails we just leave [lastActiveAt] empty and fall back to the
  // existing card UI without an online dot.
  List<dynamic>? activityRes;
  try {
    activityRes = await client.from('users').select('id, last_active_at').inFilter('id', ids) as List<dynamic>?;
  } catch (_) {
    activityRes = null;
  }
  // Tolerant family fetch — caste/subcaste for the manual Browse filters.
  List<dynamic>? familyRes;
  try {
    familyRes = await client
        .from('family_details')
        .select('user_id, caste, subcaste')
        .inFilter('user_id', ids) as List<dynamic>?;
  } catch (_) {
    familyRes = null;
  }
  final familyRows = (familyRes ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final Map<String, Map<String, dynamic>> familyByUser = {
    for (final r in familyRows)
      if (r['user_id'] != null) r['user_id'].toString(): r,
  };

  // Tolerant horoscope fetch — drives the Browse Star / Horoscope filters.
  List<dynamic>? horoscopeRes;
  try {
    horoscopeRes = await client
        .from('horoscope_details')
        .select('user_id, star, zodiac_sign, dhosham')
        .inFilter('user_id', ids) as List<dynamic>?;
  } catch (_) {
    horoscopeRes = null;
  }
  final horoscopeRows = (horoscopeRes ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final Map<String, Map<String, dynamic>> horoscopeByUser = {
    for (final r in horoscopeRows)
      if (r['user_id'] != null) r['user_id'].toString(): r,
  };

  if (casteCompulsory && prefCasteArr.isNotEmpty && !prefCasteArr.contains('Any')) {
    filtered = filtered.where((p) {
      final uid = p['user_id'].toString();
      final fam = familyByUser[uid];
      final c = fam?['caste']?.toString();
      return c != null && prefCasteArr.contains(c);
    }).toList();
  }

  final photoRows = (photosRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final contactRows = (contactRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final settingsRows = (settingsRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final eduRows = (eduRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final empRows = (empRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final busRows = (busRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final stuRows = (stuRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final interestRows = (interestsRes as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final activityRows = (activityRes ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final Map<String, DateTime?> lastActiveByUser = {
    for (final r in activityRows)
      if (r['id'] != null) r['id'].toString(): parseLastActive(r['last_active_at']),
  };

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

  bool matchArrayOrCommaStr(dynamic prefValue, String? profileValue) {
    if (prefValue == null) return true;
    List<String> prefArr = [];
    if (prefValue is List) {
      prefArr = prefValue.map((e) => e.toString()).toList();
    } else if (prefValue is String) {
      if (prefValue == 'Any' || prefValue.trim().isEmpty) return true;
      prefArr = prefValue.split(', ').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    if (prefArr.isEmpty || prefArr.contains('Any')) return true;
    if (profileValue == null || profileValue.trim().isEmpty) return false;
    return prefArr.contains(profileValue.trim());
  }

  if (applyPreferences && prefs != null) {
    filtered = filtered.where((p) {
      final uid = p['user_id'].toString();
      final fam = familyByUser[uid];
      final horo = horoscopeByUser[uid];
      final con = firstRowFor(uid, contactRows);
      final edu = firstRowFor(uid, eduRows);
      final emp = firstRowFor(uid, empRows);
      final bus = firstRowFor(uid, busRows);
      
      if (!matchArrayOrCommaStr(prefs['preferred_subcaste'], fam?['subcaste']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_star'], horo?['star']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_raasi'], horo?['zodiac_sign']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_dosham'], horo?['dhosham']?.toString())) return false;
      
      if (!matchArrayOrCommaStr(prefs['preferred_education'], edu?['education']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_degrees'], edu?['degree']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_branches'], edu?['branch']?.toString())) return false;
      
      final empIn = emp?['employment_type']?.toString() ?? bus?['business_type']?.toString();
      if (!matchArrayOrCommaStr(prefs['preferred_employed_in'], empIn)) return false;
      
      final occ = emp?['designation']?.toString() ?? bus?['designation']?.toString();
      if (!matchArrayOrCommaStr(prefs['preferred_occupation'], occ)) return false;
      
      final inc = emp?['salary']?.toString() ?? bus?['annual_returns']?.toString();
      if (!matchArrayOrCommaStr(prefs['preferred_annual_income_min'], inc)) return false;
      
      if (!matchArrayOrCommaStr(prefs['preferred_country'], con?['current_country']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_state'], con?['current_state']?.toString())) return false;
      if (!matchArrayOrCommaStr(prefs['preferred_city'], con?['current_district']?.toString())) return false;
      
      return true;
    }).toList();
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

    final horo = horoscopeByUser[id];
    final fam = familyByUser[id];

    int? poruthamScore;
    if (myHoro != null && myHoro['star'] != null && horo != null && horo['star'] != null) {
      final isFemale = p['sex']?.toString().toLowerCase() == 'female';
      final scoreRes = checkTamilPorutham(
        girlStar: isFemale ? horo['star'].toString() : myHoro['star'].toString(),
        girlRashi: isFemale ? (horo['zodiac_sign']?.toString() ?? '') : (myHoro['zodiac_sign']?.toString() ?? ''),
        boyStar: isFemale ? myHoro['star'].toString() : horo['star'].toString(),
        boyRashi: isFemale ? (myHoro['zodiac_sign']?.toString() ?? '') : (horo['zodiac_sign']?.toString() ?? ''),
      );
      poruthamScore = scoreRes.score;
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
      lastActiveAt: lastActiveByUser[id],
      createdAt: DateTime.tryParse(p['created_at']?.toString() ?? ''),
      star: horo?['star']?.toString(),
      zodiacSign: horo?['zodiac_sign']?.toString(),
      maritalStatus: p['marital_status']?.toString(),
      caste: fam?['caste']?.toString(),
      subcaste: fam?['subcaste']?.toString(),
      educationLevels: eduByUser[id] ?? const [],
      photoVerified: p['photo_verified'] == true,
      profileCode: p['profile_code']?.toString(),
      poruthamScore: poruthamScore,
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

/// Builds a list of [MatchPreview]s for an arbitrary set of `userId`s.
///
/// Used by activity carousels (Who Viewed Me / Profiles I Viewed / Interest
/// Received) and by the sidebar "search by ID" tile, which only know the
/// target ids and need the same card shape as the other dashboard sections.
///
/// Order of [orderedIds] is preserved in the result. Missing/RLS-restricted
/// rows are silently skipped.
Future<List<MatchPreview>> loadMatchPreviewsByIds(
  SupabaseClient client,
  List<String> orderedIds,
) async {
  final ids = orderedIds.where((s) => s.trim().isNotEmpty).toSet().toList();
  if (ids.isEmpty) return const [];

  final myUid = client.auth.currentUser?.id;
  Map<String, dynamic>? myHoro;
  if (myUid != null) {
    try {
      myHoro = await client
          .from('horoscope_details')
          .select('star, zodiac_sign')
          .eq('user_id', myUid)
          .maybeSingle();
    } catch (_) {}
  }

  Future<List<dynamic>> safeIn(String table, String columns, String column) async {
    try {
      final r = await client.from(table).select(columns).inFilter(column, ids);
      return (r as List<dynamic>? ?? []);
    } catch (_) {
      return const [];
    }
  }

  final personalRes = await safeIn(
    'personal_details',
    'user_id, name, age, sex, marital_status, profile_code',
    'user_id',
  );
  final personalRows =
      personalRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (personalRows.isEmpty) return const [];

  final photoRes = await safeIn('photos', 'user_id, user_photos', 'user_id');
  final contactRes = await safeIn('contact_details', 'user_id, current_district, current_state', 'user_id');
  final settingsRes = await safeIn('user_settings', 'user_id, is_premium', 'user_id');
  final eduRes = await safeIn('education_details', 'user_id, education', 'user_id');
  final empRes = await safeIn('profession_employee', 'user_id, designation, company', 'user_id');
  final busRes = await safeIn('profession_business', 'user_id, designation, business_name', 'user_id');
  final stuRes = await safeIn('profession_student', 'user_id, course, institution', 'user_id');
  final interestsRes = await safeIn('interests', 'user_id, interests', 'user_id');
  final activityRes = await safeIn('users', 'id, last_active_at', 'id');
  final horoRes = await safeIn('horoscope_details', 'user_id, star, zodiac_sign', 'user_id');

  final photoRows = photoRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final contactRows = contactRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final settingsRows = settingsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final eduRows = eduRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final empRows = empRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final busRows = busRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final stuRows = stuRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final interestRows = interestsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final activityRows = activityRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final horoRows = horoRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  final lastActiveByUser = <String, DateTime?>{
    for (final r in activityRows)
      if (r['id'] != null) r['id'].toString(): parseLastActive(r['last_active_at']),
  };

  final eduByUser = <String, List<String>>{};
  for (final row in eduRows) {
    final uid = row['user_id']?.toString();
    final ed = row['education']?.toString().trim() ?? '';
    if (uid == null || ed.isEmpty) continue;
    eduByUser.putIfAbsent(uid, () => []).add(ed);
  }
  String? lastEducationFor(String uid) =>
      eduByUser[uid]?.isNotEmpty == true ? eduByUser[uid]!.last : null;

  Map<String, dynamic>? findFor(String uid, List<Map<String, dynamic>> rows) {
    for (final r in rows) {
      if (r['user_id']?.toString() == uid) return r;
    }
    return null;
  }

  String? jobLineFor(String uid) {
    final emp = findFor(uid, empRows);
    if (emp != null) {
      final d = emp['designation']?.toString().trim() ?? '';
      final c = emp['company']?.toString().trim() ?? '';
      if (d.isNotEmpty) return d;
      if (c.isNotEmpty) return c;
    }
    final bus = findFor(uid, busRows);
    if (bus != null) {
      final d = bus['designation']?.toString().trim() ?? '';
      final n = bus['business_name']?.toString().trim() ?? '';
      if (d.isNotEmpty) return d;
      if (n.isNotEmpty) return n;
    }
    final stu = findFor(uid, stuRows);
    if (stu != null) {
      final co = stu['course']?.toString().trim() ?? '';
      final ins = stu['institution']?.toString().trim() ?? '';
      if (co.isNotEmpty) return co;
      if (ins.isNotEmpty) return ins;
    }
    return null;
  }

  List<String> interestsFor(String uid) {
    for (final r in interestRows) {
      if (r['user_id']?.toString() == uid) {
        return parseInterestsTableArrayColumn(r['interests']);
      }
    }
    return const [];
  }

  Future<MatchPreview?> buildOne(String uid) async {
    final p = findFor(uid, personalRows);
    if (p == null) return null;

    final ph = findFor(uid, photoRows);
    final photos = ph != null ? parseUserPhotosList(ph['user_photos']) : <dynamic>[];
    String? url;
    for (final raw in photos) {
      final u = await signUserProfilePhoto(client, uid, raw.toString());
      if (u != null && u.isNotEmpty) {
        url = u;
        break;
      }
    }

    final c = findFor(uid, contactRows);
    final d = c?['current_district']?.toString() ?? '';
    final s = c?['current_state']?.toString() ?? '';
    var loc = '—';
    if (d.isNotEmpty) {
      loc = s.isNotEmpty ? '$d, $s' : d;
    } else if (s.isNotEmpty) {
      loc = s;
    }

    var premium = false;
    final st = findFor(uid, settingsRows);
    if (st != null && st['is_premium'] == true) premium = true;

    final targetHoroRow = findFor(uid, horoRows);
    int? poruthamScore;
    if (myHoro != null && myHoro['star'] != null && targetHoroRow != null && targetHoroRow['star'] != null) {
      final isTargetFemale = (p['sex']?.toString().toLowerCase() == 'female') || (p['gender']?.toString().toLowerCase() == 'female');
      final scoreRes = checkTamilPorutham(
        girlStar: isTargetFemale ? targetHoroRow['star'].toString() : myHoro['star'].toString(),
        girlRashi: isTargetFemale ? (targetHoroRow['zodiac_sign']?.toString() ?? '') : (myHoro['zodiac_sign']?.toString() ?? ''),
        boyStar: isTargetFemale ? myHoro['star'].toString() : targetHoroRow['star'].toString(),
        boyRashi: isTargetFemale ? (myHoro['zodiac_sign']?.toString() ?? '') : (targetHoroRow['zodiac_sign']?.toString() ?? ''),
      );
      poruthamScore = scoreRes.score;
    }

    return MatchPreview(
      userId: uid,
      name: p['name']?.toString().trim().isNotEmpty == true ? p['name'].toString() : 'Member',
      age: p['age'] != null ? (p['age'] as num).round() : null,
      location: loc,
      photoUrl: url,
      isPremium: premium,
      educationDegree: lastEducationFor(uid),
      jobTitle: jobLineFor(uid),
      interestTags: interestsFor(uid),
      lastActiveAt: lastActiveByUser[uid],
      profileCode: p['profile_code']?.toString(),
      poruthamScore: poruthamScore,
    );
  }

  final ordered = <MatchPreview>[];
  for (final id in orderedIds) {
    final p = await buildOne(id);
    if (p != null) ordered.add(p);
  }
  return ordered;
}

/// Return shortlist id-sets for [userId]:
///  - `byMe` = ids the current user has shortlisted.
///  - `ofMe` = ids of users who have shortlisted the current user.
///
/// Tolerant of RLS / network errors — falls back to empty sets.
Future<({Set<String> byMe, Set<String> ofMe})> loadShortlistIdSets(
  SupabaseClient client,
  String userId,
) async {
  Future<List<Map<String, dynamic>>> safe(String column, String value) async {
    try {
      final r = await client
          .from('shortlists')
          .select('user_id, shortlisted_user_id')
          .eq(column, value)
          .limit(500);
      return (r as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  final byMeRows = await safe('user_id', userId);
  final ofMeRows = await safe('shortlisted_user_id', userId);
  final byMe = <String>{
    for (final r in byMeRows)
      if (r['shortlisted_user_id'] != null) r['shortlisted_user_id'].toString(),
  };
  final ofMe = <String>{
    for (final r in ofMeRows)
      if (r['user_id'] != null) r['user_id'].toString(),
  };
  return (byMe: byMe, ofMe: ofMe);
}

/// Return the set of user ids the current user has hidden via the
/// `ignored_profiles` table (manavizha `/api/ignores`). RLS-tolerant.
Future<Set<String>> loadIgnoredProfileIds(SupabaseClient client, String userId) async {
  try {
    final r = await client
        .from('ignored_profiles')
        .select('ignored_user_id')
        .eq('user_id', userId)
        .limit(500);
    return {
      for (final row in (r as List<dynamic>))
        if ((row as Map)['ignored_user_id'] != null) (row['ignored_user_id']).toString(),
    };
  } catch (_) {
    return const {};
  }
}

/// Return the set of user ids the current user has blocked via the
/// `blocked_profiles` table (manavizha `/api/blocks` GET). RLS-tolerant.
Future<Set<String>> loadBlockedProfileIds(SupabaseClient client, String userId) async {
  try {
    final r = await client
        .from('blocked_profiles')
        .select('blocked_user_id')
        .eq('user_id', userId)
        .limit(500);
    return {
      for (final row in (r as List<dynamic>))
        if ((row as Map)['blocked_user_id'] != null) (row['blocked_user_id']).toString(),
    };
  } catch (_) {
    return const {};
  }
}
