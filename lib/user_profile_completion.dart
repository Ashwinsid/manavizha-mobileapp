import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Completion 0–100 for each category on [UserDetailsPage] (same rules as [loadUserProfileSnapshot]).
class UserDetailsSectionCompletion {
  const UserDetailsSectionCompletion({
    required this.basicDetails,
    required this.educationalDetails,
    required this.professionalDetails,
    required this.familyDetails,
    required this.horoscopeDetails,
    required this.interests,
    required this.socialHabits,
  });

  final int basicDetails;
  final int educationalDetails;
  final int professionalDetails;
  final int familyDetails;
  final int horoscopeDetails;
  final int interests;
  final int socialHabits;
}

/// Mirrors [manavizha/components/user-landing-page.tsx] profile progress logic.
class UserProfileSnapshot {
  UserProfileSnapshot({
    required this.completionPercent,
    required this.sections,
    this.name,
    required this.photoVerified,
    this.firstPhotoSignedUrl,
    this.familyPhotoUrl,
    required this.isPremium,
    this.premiumPlan,
    this.maritalStatus,
    required this.userPhotoCount,
    required this.hasFamilyPhoto,
  });

  final int completionPercent;
  final UserDetailsSectionCompletion sections;
  final String? name;
  final bool photoVerified;
  final String? firstPhotoSignedUrl;
  final String? familyPhotoUrl;
  final bool isPremium;
  final String? premiumPlan;
  final String? maritalStatus;
  final int userPhotoCount;
  final bool hasFamilyPhoto;
}

int _nonEmptyListItemCount(List<dynamic> list) =>
    list.where((e) => e != null && e.toString().trim().isNotEmpty && e.toString() != 'null').length;

/// Basic Details — same field rules as dashboard / [loadUserProfileSnapshot]. Used when saving [personal_details].
int computePersonalDetailsCompletionPercent(Map<String, dynamic>? personal) {
  if (personal == null) return 0;
  const fields = [
    'name',
    'date_of_birth',
    'age',
    'sex',
    'height',
    'weight',
    'skin_color',
    'body_type',
    'marital_status',
    'about',
    'food_preference',
    'languages',
  ];
  var filled = 0;
  for (final f in fields) {
    final val = personal[f];
    if (f == 'languages') {
      if (val is List && val.isNotEmpty) filled++;
    } else if (val != null && val.toString().trim().isNotEmpty) {
      filled++;
    }
  }
  return ((filled / fields.length) * 100).round();
}

int computeContactCompletionPercent(Map<String, dynamic>? contact) {
  if (contact == null) return 0;
  const fields = [
    'phone',
    'whatsapp_number',
    'permanent_address_line1',
    'permanent_pincode',
    'permanent_area',
    'permanent_taluk',
    'permanent_district',
    'permanent_division',
    'permanent_region',
    'permanent_state',
    'permanent_country',
    'current_address_line1',
    'current_pincode',
    'current_area',
    'current_taluk',
    'current_district',
    'current_division',
    'current_region',
    'current_state',
    'current_country',
  ];
  var filled = 0;
  for (final f in fields) {
    final val = contact[f];
    if (val != null && val.toString().trim().isNotEmpty) filled++;
  }
  return ((filled / fields.length) * 100).round();
}

int computeFamilyDetailsCompletionPercent(Map<String, dynamic>? family) {
  if (family == null) return 0;
  const fields = [
    'father_name',
    'father_occupation',
    'mother_name',
    'mother_occupation',
    'parents_address_line1',
    'parents_pincode',
    'parents_area',
    'parents_taluk',
    'parents_district',
    'parents_division',
    'parents_region',
    'parents_state',
    'parents_country',
    'caste',
    'family_type',
    'family_status',
  ];
  var filled = 0;
  for (final f in fields) {
    final val = family[f];
    if (val != null && val.toString().trim().isNotEmpty) filled++;
  }
  return ((filled / fields.length) * 100).round();
}

int computeHoroscopeCompletionPercent(Map<String, dynamic>? horoscope) {
  if (horoscope == null) return 0;
  const fields = ['jaadhagam_url', 'time_of_birth', 'place_of_birth', 'zodiac_sign', 'star', 'lagnam', 'dhosham'];
  var filled = 0;
  for (final f in fields) {
    final val = horoscope[f];
    if (val != null && val.toString().trim().isNotEmpty) filled++;
  }
  return ((filled / fields.length) * 100).round();
}

int _countFilledKeys(Map<String, dynamic> m, List<String> keys) {
  var n = 0;
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().trim().isNotEmpty) n++;
  }
  return n;
}

bool _rowHasAnyKey(Map<String, dynamic>? m, List<String> keys) =>
    m != null && keys.any((k) => m[k] != null && m[k].toString().trim().isNotEmpty);

/// Matches [ProfileExtendedRepository.detectProfessionType] routing.
int computeProfessionSectionPercent(Map<String, dynamic>? empData, Map<String, dynamic>? busData, Map<String, dynamic>? stuData) {
  if (_rowHasAnyKey(empData, ['designation', 'company', 'sector'])) {
    final n = _countFilledKeys(empData!, ['sector', 'company', 'designation', 'salary', 'work_location']);
    return ((n / 5) * 100).round();
  }
  if (_rowHasAnyKey(busData, ['business_name', 'designation'])) {
    final n = _countFilledKeys(busData!, ['sector', 'business_name', 'designation', 'annual_returns', 'business_location']);
    return ((n / 5) * 100).round();
  }
  if (_rowHasAnyKey(stuData, ['course', 'institution'])) {
    final n = _countFilledKeys(stuData!, ['institution', 'course', 'field_of_study']);
    return ((n / 3) * 100).round();
  }
  return 0;
}

/// Hobbies + interests each contribute up to half (need 3 each for 100%).
int computeInterestsSectionPercent(Map<String, dynamic>? interests) {
  if (interests == null) return 0;
  final hobbies = interests['hobbies'] as List<dynamic>? ?? [];
  final userInterests = interests['interests'] as List<dynamic>? ?? [];
  final h = _nonEmptyListItemCount(hobbies);
  final i = _nonEmptyListItemCount(userInterests);
  final part = (math.min(h, 3) / 3 + math.min(i, 3) / 3) / 2;
  return (part * 100).round();
}

int computeSocialHabitsCompletionPercent(Map<String, dynamic>? social) {
  if (social == null) return 0;
  const fields = ['smoking', 'drinking', 'parties', 'pubs'];
  var filled = 0;
  for (final f in fields) {
    final val = social[f];
    if (val != null && val.toString().trim().isNotEmpty) filled++;
  }
  return ((filled / fields.length) * 100).round();
}

double calculateTrustScore({
  required bool photoVerified,
  required int completionPercentage,
  int photoCount = 0,
  bool hasFamilyPhoto = false,
}) {
  var score = 1.0;
  if (photoVerified) score += 3.0;
  score += (completionPercentage / 100) * 3.0;
  score += math.min(photoCount * 0.4, 2.0);
  if (hasFamilyPhoto) score += 1.0;
  final rounded = (score * 10).round() / 10.0;
  return math.min(rounded, 10.0);
}

Future<UserProfileSnapshot> loadUserProfileSnapshot(SupabaseClient client, String userId) async {
  final results = await Future.wait<dynamic>([
    client
        .from('personal_details')
        .select(
          'name, date_of_birth, age, sex, height, weight, skin_color, body_type, marital_status, about, food_preference, languages, photo_verified',
        )
        .eq('user_id', userId)
        .maybeSingle(),
    client
        .from('contact_details')
        .select(
          'phone, whatsapp_number, permanent_address_line1, permanent_pincode, permanent_area, permanent_taluk, permanent_district, permanent_division, permanent_region, permanent_state, permanent_country, current_address_line1, current_pincode, current_area, current_taluk, current_district, current_division, current_region, current_state, current_country',
        )
        .eq('user_id', userId)
        .maybeSingle(),
    client.from('education_details').select('education').eq('user_id', userId),
    client
        .from('profession_employee')
        .select('sector, company, designation, salary, work_location')
        .eq('user_id', userId)
        .maybeSingle(),
    client
        .from('profession_business')
        .select('sector, business_name, designation, annual_returns, business_location')
        .eq('user_id', userId)
        .maybeSingle(),
    client.from('profession_student').select('institution, course, field_of_study').eq('user_id', userId).maybeSingle(),
    client
        .from('family_details')
        .select(
          'father_name, father_occupation, mother_name, mother_occupation, parents_address_line1, parents_pincode, parents_area, parents_taluk, parents_district, parents_division, parents_region, parents_state, parents_country, caste, family_type, family_status',
        )
        .eq('user_id', userId)
        .maybeSingle(),
    client.from('horoscope_details').select('jaadhagam_url, time_of_birth, place_of_birth, zodiac_sign, star, lagnam, dhosham').eq('user_id', userId).maybeSingle(),
    client.from('interests').select('hobbies, interests').eq('user_id', userId).maybeSingle(),
    client.from('social_habits').select('smoking, drinking, parties, pubs').eq('user_id', userId).maybeSingle(),
    client.from('photos').select('user_photos, family_photo, aadhar_front, aadhar_back').eq('user_id', userId).maybeSingle(),
    client.from('user_settings').select('is_premium, premium_plan, premium_expires_at').eq('user_id', userId).maybeSingle(),
  ]);

  final personal = results[0] as Map<String, dynamic>?;
  final contact = results[1] as Map<String, dynamic>?;
  final eduData = results[2] as List<dynamic>? ?? [];
  final empData = results[3] as Map<String, dynamic>?;
  final busData = results[4] as Map<String, dynamic>?;
  final stuData = results[5] as Map<String, dynamic>?;
  final family = results[6] as Map<String, dynamic>?;
  final horoscope = results[7] as Map<String, dynamic>?;
  final interests = results[8] as Map<String, dynamic>?;
  final social = results[9] as Map<String, dynamic>?;
  final photos = results[10] as Map<String, dynamic>?;
  final settings = results[11] as Map<String, dynamic>?;

  final personalProgress = computePersonalDetailsCompletionPercent(personal);
  final contactProgress = computeContactCompletionPercent(contact);

  var eduProgress = 0;
  if (eduData.isNotEmpty) {
    final hasData = eduData.any((edu) {
      final m = Map<String, dynamic>.from(edu as Map);
      final e = m['education']?.toString() ?? '';
      return e.isNotEmpty;
    });
    eduProgress = hasData ? 100 : 0;
  }

  final profProgress = computeProfessionSectionPercent(empData, busData, stuData);
  final familyProgress = computeFamilyDetailsCompletionPercent(family);
  final horoscopeProgress = computeHoroscopeCompletionPercent(horoscope);
  final interestsProgress = computeInterestsSectionPercent(interests);
  final socialProgress = computeSocialHabitsCompletionPercent(social);

  var photosProgress = 0;
  if (photos != null) {
    final userPhotos = parseUserPhotosList(photos['user_photos']);
    final fam = photos['family_photo']?.toString();
    final a1 = photos['aadhar_front']?.toString();
    final a2 = photos['aadhar_back']?.toString();
    if (userPhotos.length >= 3 && fam != null && fam.isNotEmpty && a1 != null && a1.isNotEmpty && a2 != null && a2.isNotEmpty) {
      photosProgress = 100;
    }
  }

  final hasStartedProfile = personalProgress > 0 || contactProgress > 0;
  final referralProgress = hasStartedProfile ? 100 : 0;

  final stepProgresses = [
    personalProgress,
    contactProgress,
    eduProgress,
    profProgress,
    familyProgress,
    horoscopeProgress,
    interestsProgress,
    socialProgress,
    photosProgress,
    referralProgress,
  ];

  final total = stepProgresses.fold<int>(0, (a, b) => a + b);
  final averageProgress = hasStartedProfile ? (total / stepProgresses.length).round() : 0;

  String? firstSigned;
  var userPhotoCount = 0;
  var hasFamilyPhoto = false;
  if (photos != null) {
    final userPhotos = parseUserPhotosList(photos['user_photos']);
    userPhotoCount = userPhotos.length;
    final fam = photos['family_photo']?.toString() ?? '';
    hasFamilyPhoto = fam.isNotEmpty;
    if (userPhotos.isNotEmpty) {
      final raw = userPhotos.first?.toString() ?? '';
      firstSigned = await signUserProfilePhoto(client, userId, raw);
    }
  }

  final photoVerified = personal?['photo_verified'] == true;
  final name = personal?['name']?.toString();
  String? marital = personal?['marital_status']?.toString();
  if (marital != null && marital.isNotEmpty) {
    marital = marital[0].toUpperCase() + marital.substring(1).toLowerCase();
  }

  final isPremium = settings?['is_premium'] == true;
  final premiumPlan = settings?['premium_plan']?.toString();

  return UserProfileSnapshot(
    completionPercent: averageProgress.clamp(0, 100),
    sections: UserDetailsSectionCompletion(
      basicDetails: personalProgress.clamp(0, 100),
      educationalDetails: eduProgress.clamp(0, 100),
      professionalDetails: profProgress.clamp(0, 100),
      familyDetails: familyProgress.clamp(0, 100),
      horoscopeDetails: horoscopeProgress.clamp(0, 100),
      interests: interestsProgress.clamp(0, 100),
      socialHabits: socialProgress.clamp(0, 100),
    ),
    name: name,
    photoVerified: photoVerified,
    firstPhotoSignedUrl: firstSigned,
    familyPhotoUrl: photos?['family_photo']?.toString(),
    isPremium: isPremium,
    premiumPlan: premiumPlan,
    maritalStatus: marital,
    userPhotoCount: userPhotoCount,
    hasFamilyPhoto: hasFamilyPhoto,
  );
}

/// Normalizes [photos.user_photos] from PostgREST (json array or occasional json string).
List<dynamic> parseUserPhotosList(dynamic v) {
  if (v == null) return [];
  if (v is List) return List<dynamic>.from(v);
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return [];
    try {
      final d = jsonDecode(t);
      if (d is List) return List<dynamic>.from(d);
    } catch (_) {}
  }
  return [];
}

/// Object path inside the `user-photos` bucket from a Supabase storage or API URL.
String? _storageObjectPathForUserPhotosUrl(String url) {
  try {
    final uri = Uri.parse(url.trim());
    final segs = uri.pathSegments;
    const bucket = 'user-photos';
    final i = segs.indexOf(bucket);
    if (i >= 0 && i + 1 < segs.length) {
      return segs.sublist(i + 1).join('/');
    }
  } catch (_) {}
  return null;
}

/// Resolves a [user_photos] entry to a displayable URL.
///
/// DB values are often full `sign` or `public` URLs (saved at upload time). Those can expire
/// or not work for other viewers; we extract the object path and call [createSignedUrl] with
/// the **current** session so storage RLS applies to the viewer.
/// Returns null only when signing fails and no usable fallback exists.
Future<String?> signUserProfilePhoto(SupabaseClient client, String userId, String photo) async {
  final raw = photo.trim();
  if (raw.isEmpty) return null;
  try {
    if (!raw.startsWith('http')) {
      var filePath = raw;
      if (!filePath.contains('/')) filePath = '$userId/$filePath';
      return await client.storage.from('user-photos').createSignedUrl(filePath, 31536000);
    }

    final fromUrl = _storageObjectPathForUserPhotosUrl(raw);
    if (fromUrl != null && fromUrl.isNotEmpty) {
      try {
        return await client.storage.from('user-photos').createSignedUrl(fromUrl, 31536000);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('signUserProfilePhoto re-sign from URL path ($userId): $e');
        }
      }
    }

    if (raw.contains('/user-photos/')) {
      final parts = raw.split('/user-photos/');
      if (parts.length > 1) {
        var path = parts[1].split('?').first;
        if (path.startsWith('/')) path = path.substring(1);
        if (path.isNotEmpty) {
          try {
            return await client.storage.from('user-photos').createSignedUrl(path, 31536000);
          } catch (e) {
            if (kDebugMode) debugPrint('signUserProfilePhoto legacy split ($userId): $e');
          }
        }
      }
    }

    return raw;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('signUserProfilePhoto skipped ($userId): $e');
    }
    return null;
  }
}
