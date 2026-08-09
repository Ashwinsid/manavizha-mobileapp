import 'astrology.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dart ports of the two scoring functions in `manavizha/lib`:
/// - `lib/matching.ts`            → [calculateLifestyleScore]
/// - `lib/astrology.ts`           → [checkTamilPorutham]
///
/// (`calculateTrustScore` already lives in [user_profile_completion.dart].)
///
/// Plus a small loader that pulls the data needed for lifestyle / porutham
/// scoring from Supabase ([loadCompatibilityProfile]) so the dashboard can
/// compute breakdowns on tap.

class LifestyleBreakdown {
  const LifestyleBreakdown({
    required this.category,
    required this.label,
    required this.score,
    required this.details,
  });

  final String category;
  final String label;
  final double score;
  final List<String> details;
}

class LifestyleResult {
  const LifestyleResult({required this.totalScore, required this.breakdown});

  final int totalScore;
  final List<LifestyleBreakdown> breakdown;
}

/// Compatibility input shape — flat map keys mirror `FormData`/`profile`
/// shape used by the web `calculateLifestyleScore`.
class CompatibilityProfile {
  const CompatibilityProfile({
    this.foodPreference,
    this.smoking,
    this.drinking,
    this.hobbies = const [],
    this.interests = const [],
    this.workLocation,
    this.currentDistrict,
    this.sector,
    this.salary,
    this.star,
    this.zodiacSign,
    this.sex,
  });

  final String? foodPreference;
  final String? smoking;
  final String? drinking;
  final List<String> hobbies;
  final List<String> interests;
  final String? workLocation;
  final String? currentDistrict;
  final String? sector;
  final String? salary;
  final String? star;
  final String? zodiacSign;
  final String? sex;
}

/// Lifestyle compatibility — port of `calculateLifestyleScore`.
LifestyleResult calculateLifestyleScore(CompatibilityProfile user, CompatibilityProfile partner) {
  // --- Tier 1: Dealbreakers (50%) ---
  var tier1 = 0.0;
  final tier1Details = <String>[];
  final uFood = (user.foodPreference ?? '').trim();
  final pFood = (partner.foodPreference ?? '').trim();
  if (uFood.isNotEmpty && pFood.isNotEmpty && uFood == pFood) {
    tier1 += 25;
    tier1Details.add('Both prefer $uFood food');
  } else {
    final uVeg = uFood.contains('Veg') && !uFood.contains('Non-Veg');
    final pNon = pFood.contains('Non-Veg');
    if (uVeg && pNon) {
      tier1 += 0;
    } else {
      tier1 += 10;
    }
  }
  final habitsMatch = user.smoking == partner.smoking && user.drinking == partner.drinking;
  if (habitsMatch) {
    tier1 += 25;
    tier1Details.add('Compatible social habits');
  } else {
    tier1 += 5;
  }

  // --- Tier 2: Lifestyle (30%) ---
  final userInterests = <String>[...user.hobbies, ...user.interests];
  final partnerInterests = <String>[...partner.hobbies, ...partner.interests];
  final common = userInterests.where(partnerInterests.contains).toList();
  double interestScore;
  if (userInterests.isEmpty) {
    interestScore = 50;
  } else {
    final maxLen = userInterests.length > partnerInterests.length
        ? userInterests.length
        : partnerInterests.length;
    interestScore = maxLen == 0 ? 50 : (common.length / maxLen) * 100;
  }
  final tier2Details = <String>[];
  if (common.isNotEmpty) {
    tier2Details.add('Shared interests in ${common.take(2).join(', ')}');
  }

  // --- Tier 3: Future (20%) ---
  var tier3 = 0.0;
  final tier3Details = <String>[];
  final sameLoc = (user.workLocation != null && user.workLocation == partner.workLocation) ||
      (user.currentDistrict != null && user.currentDistrict == partner.currentDistrict);
  if (sameLoc) {
    tier3 += 50;
    tier3Details.add('Same work location or home town');
  } else {
    tier3 += 25;
  }
  if (user.sector != null && user.sector == partner.sector) {
    tier3 += 50;
    tier3Details.add('Both work in ${user.sector} sector');
  } else {
    tier3 += 25;
  }

  final breakdown = <LifestyleBreakdown>[
    LifestyleBreakdown(
      category: 'Dealbreakers',
      label: 'Values & Habits',
      score: tier1 * 2, // scaled to /100 to match web display
      details: tier1Details,
    ),
    LifestyleBreakdown(
      category: 'Lifestyle',
      label: 'Vibe & Hobbies',
      score: interestScore,
      details: tier2Details,
    ),
    LifestyleBreakdown(
      category: 'Future',
      label: 'Career & Goals',
      score: tier3,
      details: tier3Details,
    ),
  ];

  // Final weighted score: T1 50% + T2 30% + T3 20% — same arithmetic as web.
  final total = ((tier1 * 2) * 0.5 + interestScore * 0.3 + tier3 * 0.2).round();
  return LifestyleResult(totalScore: total, breakdown: breakdown);
}

class PoruthamResult {
  const PoruthamResult({required this.score, required this.status, required this.breakdown});

  final int score;
  final String status; // Uthamam | Madhyamam | Athamam
  final Map<String, bool> breakdown;
}

const _nakshatras = <String>[
  'Ashwini', 'Bharani', 'Krithika', 'Rohini', 'Mrigashira', 'Ardra', 'Punarvasu',
  'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni', 'Hasta',
  'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha', 'Mula', 'Purva Ashadha',
  'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha', 'Purva Bhadrapada',
  'Uttara Bhadrapada', 'Revati',
];

const _rashis = <String>[
  'Mesha', 'Vrishabha', 'Mithuna', 'Karka', 'Simha', 'Kanya', 'Tula',
  'Vrishchika', 'Dhanu', 'Makara', 'Kumbha', 'Meena',
];

const _nakshatraData = <String, Map<String, String>>{
  'Ashwini': {'gana': 'Deva', 'yoni': 'Horse', 'rajju': 'Foot', 'vedha': 'Jyeshtha'},
  'Bharani': {'gana': 'Manushya', 'yoni': 'Elephant', 'rajju': 'Thigh', 'vedha': 'Anuradha'},
  'Krithika': {'gana': 'Rakshasa', 'yoni': 'Goat', 'rajju': 'Hip', 'vedha': 'Vishakha'},
  'Rohini': {'gana': 'Manushya', 'yoni': 'Serpent', 'rajju': 'Navel', 'vedha': 'Swati'},
  'Mrigashira': {'gana': 'Deva', 'yoni': 'Serpent', 'rajju': 'Neck', 'vedha': 'Chitra'},
  'Ardra': {'gana': 'Manushya', 'yoni': 'Dog', 'rajju': 'Neck', 'vedha': 'Shravana'},
  'Punarvasu': {'gana': 'Deva', 'yoni': 'Cat', 'rajju': 'Navel', 'vedha': 'Uttara Ashadha'},
  'Pushya': {'gana': 'Deva', 'yoni': 'Sheep', 'rajju': 'Hip', 'vedha': 'Purva Ashadha'},
  'Ashlesha': {'gana': 'Rakshasa', 'yoni': 'Cat', 'rajju': 'Thigh', 'vedha': 'Mula'},
  'Magha': {'gana': 'Rakshasa', 'yoni': 'Rat', 'rajju': 'Foot', 'vedha': 'Revati'},
  'Purva Phalguni': {'gana': 'Manushya', 'yoni': 'Rat', 'rajju': 'Thigh', 'vedha': 'Uttara Bhadrapada'},
  'Uttara Phalguni': {'gana': 'Manushya', 'yoni': 'Cow', 'rajju': 'Hip', 'vedha': 'Purva Bhadrapada'},
  'Hasta': {'gana': 'Deva', 'yoni': 'Buffalo', 'rajju': 'Navel', 'vedha': 'Shatabhisha'},
  'Chitra': {'gana': 'Rakshasa', 'yoni': 'Tiger', 'rajju': 'Neck', 'vedha': 'Mrigashira'},
  'Swati': {'gana': 'Deva', 'yoni': 'Buffalo', 'rajju': 'Navel', 'vedha': 'Rohini'},
  'Vishakha': {'gana': 'Rakshasa', 'yoni': 'Tiger', 'rajju': 'Hip', 'vedha': 'Krithika'},
  'Anuradha': {'gana': 'Deva', 'yoni': 'Deer', 'rajju': 'Thigh', 'vedha': 'Bharani'},
  'Jyeshtha': {'gana': 'Rakshasa', 'yoni': 'Deer', 'rajju': 'Foot', 'vedha': 'Ashwini'},
  'Mula': {'gana': 'Rakshasa', 'yoni': 'Dog', 'rajju': 'Foot', 'vedha': 'Ashlesha'},
  'Purva Ashadha': {'gana': 'Manushya', 'yoni': 'Monkey', 'rajju': 'Thigh', 'vedha': 'Pushya'},
  'Uttara Ashadha': {'gana': 'Manushya', 'yoni': 'Mongoose', 'rajju': 'Hip', 'vedha': 'Punarvasu'},
  'Shravana': {'gana': 'Deva', 'yoni': 'Monkey', 'rajju': 'Neck', 'vedha': 'Ardra'},
  'Dhanishta': {'gana': 'Rakshasa', 'yoni': 'Lion', 'rajju': 'Neck', 'vedha': 'Shatabhisha'},
  'Shatabhisha': {'gana': 'Rakshasa', 'yoni': 'Horse', 'rajju': 'Navel', 'vedha': 'Hasta'},
  'Purva Bhadrapada': {'gana': 'Manushya', 'yoni': 'Lion', 'rajju': 'Hip', 'vedha': 'Uttara Phalguni'},
  'Uttara Bhadrapada': {'gana': 'Manushya', 'yoni': 'Cow', 'rajju': 'Thigh', 'vedha': 'Purva Phalguni'},
  'Revati': {'gana': 'Deva', 'yoni': 'Elephant', 'rajju': 'Foot', 'vedha': 'Magha'},
};

const _rashiLords = <String, String>{
  'Mesha': 'Mars', 'Vrishabha': 'Venus', 'Mithuna': 'Mercury', 'Karka': 'Moon',
  'Simha': 'Sun', 'Kanya': 'Mercury', 'Tula': 'Venus', 'Vrishchika': 'Mars',
  'Dhanu': 'Jupiter', 'Makara': 'Saturn', 'Kumbha': 'Saturn', 'Meena': 'Jupiter',
};

const _friendship = <String, List<String>>{
  'Sun': ['Moon', 'Mars', 'Jupiter'],
  'Moon': ['Sun', 'Mercury'],
  'Mars': ['Sun', 'Moon', 'Jupiter'],
  'Mercury': ['Sun', 'Venus'],
  'Jupiter': ['Sun', 'Moon', 'Mars'],
  'Venus': ['Mercury', 'Saturn'],
  'Saturn': ['Mercury', 'Venus'],
};

String _strip(String s) {
  // The DB sometimes carries the Tamil-script suffix `Krithika (கார்த்திகை)`.
  return s.split(' (').first.trim();
}

String? _findMatch(String raw, List<String> options, [Map<String, String>? fallbackMap]) {
  final cleanRaw = _strip(raw).toLowerCase().replaceAll(' ', '');
  for (final opt in options) {
    if (opt.toLowerCase().replaceAll(' ', '') == cleanRaw) return opt;
  }
  if (fallbackMap != null) {
    for (final entry in fallbackMap.entries) {
      final cleanVal = _strip(entry.value).toLowerCase().replaceAll(' ', '');
      if (cleanVal == cleanRaw) return entry.key;
    }
  }
  return null;
}

/// Tamil 10-Porutham — port of `checkTamilPorutham`. Empty inputs return 0/Athamam.
PoruthamResult checkTamilPorutham({
  required String girlStar,
  required String girlRashi,
  required String boyStar,
  required String boyRashi,
}) {
  final gStar = _findMatch(girlStar, _nakshatras, nakshatraTamil) ?? _strip(girlStar);
  final bStar = _findMatch(boyStar, _nakshatras, nakshatraTamil) ?? _strip(boyStar);
  final gRashi = _findMatch(girlRashi, _rashis, rashiTamil) ?? _strip(girlRashi);
  final bRashi = _findMatch(boyRashi, _rashis, rashiTamil) ?? _strip(boyRashi);

  final gData = _nakshatraData[gStar];
  final bData = _nakshatraData[bStar];
  if (gData == null || bData == null) {
    return const PoruthamResult(score: 0, status: 'Athamam', breakdown: {});
  }

  final gIdx = _nakshatras.indexOf(gStar);
  final bIdx = _nakshatras.indexOf(bStar);
  final gRIdx = _rashis.indexOf(gRashi);
  final bRIdx = _rashis.indexOf(bRashi);

  final breakdown = <String, bool>{};
  var matched = 0;
  void mark(String key, bool ok) {
    breakdown[key] = ok;
    if (ok) matched++;
  }

  // 1. Dina
  final dinaDist = ((bIdx - gIdx + 27) % 27) + 1;
  mark('Dina', const [2, 4, 6, 8, 9, 11, 13, 15, 17, 18, 20, 22, 24, 26, 27].contains(dinaDist));

  // 2. Gana
  final gG = gData['gana']!;
  final bG = bData['gana']!;
  bool gana = false;
  if (gG == bG) {
    gana = true;
  } else if (gG == 'Deva' && bG == 'Manushya') {
    gana = true;
  } else if (gG == 'Manushya' && bG == 'Deva') {
    gana = true;
  }
  mark('Gana', gana);

  // 3. Mahendra
  mark('Mahendra', const [4, 7, 10, 13, 16, 19, 22, 25].contains(dinaDist));

  // 4. Stree Deerkha
  mark('Stree Deerkha', ((bIdx - gIdx + 27) % 27) > 13);

  // 5. Yoni
  const avoidYoni = <String, String>{
    'Horse': 'Buffalo', 'Elephant': 'Lion', 'Sheep': 'Monkey',
    'Serpent': 'Mongoose', 'Tiger': 'Goat', 'Rat': 'Cat', 'Dog': 'Deer',
  };
  final gY = gData['yoni']!;
  final bY = bData['yoni']!;
  mark('Yoni', avoidYoni[gY] != bY && avoidYoni[bY] != gY);

  // 6. Rasi
  final rasiDist = ((bRIdx - gRIdx + 12) % 12) + 1;
  mark('Rasi', !const [2, 3, 4, 5, 6].contains(rasiDist) && rasiDist != 1);

  // 7. Rasiyathipathi
  final gLord = _rashiLords[gRashi];
  final bLord = _rashiLords[bRashi];
  final rasiLordOk = gLord != null && bLord != null &&
      (gLord == bLord ||
          (_friendship[gLord]?.contains(bLord) ?? false) ||
          (_friendship[bLord]?.contains(gLord) ?? false));
  mark('Rasiyathipathi', rasiLordOk);

  // 8. Vasya (simplified, matches web)
  const vasyaMap = <String, List<String>>{
    'Mesha': ['Simha', 'Vrishchika'],
    'Vrishabha': ['Karka', 'Tula'],
  };
  mark('Vasya', vasyaMap[gRashi]?.contains(bRashi) ?? false);

  // 9. Vedha (should NOT match)
  mark('Vedha', gData['vedha'] != bStar);

  // 10. Rajju (should NOT be on same rajju)
  mark('Rajju', gData['rajju'] != bData['rajju']);

  String status;
  if (matched >= 7) {
    status = 'Uthamam';
  } else if (matched >= 5) {
    status = 'Madhyamam';
  } else {
    status = 'Athamam';
  }
  return PoruthamResult(score: matched, status: status, breakdown: breakdown);
}

/// Loads enough fields to compute lifestyle score + porutham for [userId].
/// Returns nulls when the row is missing or RLS-restricted.
Future<CompatibilityProfile> loadCompatibilityProfile(SupabaseClient client, String userId) async {
  Future<Map<String, dynamic>?> safeOne(String table, {String column = 'user_id'}) async {
    try {
      final r = await client.from(table).select().eq(column, userId).maybeSingle();
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return null;
    }
  }

  final personal = await safeOne('personal_details');
  final contact = await safeOne('contact_details');
  final interests = await safeOne('interests');
  final social = await safeOne('social_habits');
  final emp = await safeOne('profession_employee');
  final bus = await safeOne('profession_business');
  final horo = await safeOne('horoscope_details');

  List<String> stringList(dynamic v) {
    if (v == null) return const [];
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  return CompatibilityProfile(
    foodPreference: personal?['food_preference']?.toString(),
    smoking: social?['smoking']?.toString(),
    drinking: social?['drinking']?.toString(),
    hobbies: stringList(interests?['hobbies']),
    interests: stringList(interests?['interests']),
    workLocation: emp?['work_location']?.toString() ?? bus?['business_location']?.toString(),
    currentDistrict: contact?['current_district']?.toString(),
    sector: emp?['sector']?.toString() ?? bus?['business_type']?.toString(),
    salary: emp?['salary']?.toString() ?? bus?['annual_returns']?.toString(),
    star: horo?['star']?.toString(),
    zodiacSign: horo?['zodiac_sign']?.toString(),
    sex: personal?['sex']?.toString() ?? personal?['gender']?.toString(),
  );
}
