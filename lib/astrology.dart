/// Dart port of [manavizha/lib/astrology.ts] — Vedic horoscope engine for the
/// in-app Generate Horoscope page.
///
/// The web file optionally calls `vedic-astro` (Node only) for true sidereal
/// planet positions. There is no equivalent Dart library, so this port mirrors
/// the **mean-motion fallback** code path the web also keeps (look for the
/// `try { require('vedic-astro') } catch` block in the TS file).
///
/// What that means in practice:
/// • Sun, Moon and Lagnam use the same Meeus reductions as the TS file.
/// • Mercury/Venus/Mars/Jupiter/Saturn/Rahu/Ketu use mean motions (linear
///   approximations), so they're slightly less accurate than a true ephemeris
///   — same trade-off as the web's fallback.
/// • Tithi, Yoga, Nakshatra, Rasi, Lagnam labels, Navamsam mapping, and
///   Vimshottari Dasa are bit-for-bit ports of the TS implementation.
library;

import 'dart:math' as math;

class Location {
  const Location({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

class PlanetPosition {
  PlanetPosition({
    required this.name,
    required this.tamilName,
    required this.tamilAbbr,
    required this.longitude,
    required this.siderealLongitude,
    required this.rasiIndex,
    required this.navamsamIndex,
    this.isLagnam = false,
  });

  final String name;
  final String tamilName;
  final String tamilAbbr;
  final double longitude;
  final double siderealLongitude;
  final int rasiIndex;
  final int navamsamIndex;
  final bool isLagnam;
}

class DasaPeriod {
  const DasaPeriod({
    required this.dasa,
    required this.bhukti,
    required this.start,
    required this.end,
    required this.endMs,
  });
  final String dasa;
  final String bhukti;
  final String start;
  final String end;
  final int endMs;
}

class PapaPulligalRow {
  const PapaPulligalRow({
    required this.planet,
    required this.v1,
    required this.p1,
    required this.v2,
    required this.p2,
    required this.v3,
    required this.p3,
  });
  final String planet;
  final int v1;
  final String p1;
  final int v2;
  final String p2;
  final int v3;
  final String p3;
}

class PapaPulligal {
  const PapaPulligal({
    required this.rows,
    required this.totalP1,
    required this.totalP2,
    required this.totalP3,
    required this.sevvaiDosham,
    required this.rahuDosham,
  });
  final List<PapaPulligalRow> rows;
  final String totalP1;
  final String totalP2;
  final String totalP3;
  final String sevvaiDosham;
  final String rahuDosham;
}

class HoroscopeDetails {
  const HoroscopeDetails({
    required this.star,
    required this.rashi,
    required this.lagnam,
    required this.yoga,
    required this.karana,
    required this.sunrise,
    required this.sunset,
    required this.planets,
    required this.nakshatraIndex,
    required this.tithiIndex,
    this.dasaPeriods = const [],
    this.papaPulligal,
    this.calculationMethod = 'thirukanitham',
    this.isManual = false,
  });

  final String star;
  final String rashi;
  final String lagnam;
  final String yoga;
  final String karana;
  final String sunrise;
  final String sunset;
  final List<PlanetPosition> planets;
  final int nakshatraIndex;
  final int tithiIndex;
  final List<DasaPeriod> dasaPeriods;
  final PapaPulligal? papaPulligal;
  final String calculationMethod;
  final bool isManual;
}

// Tamil-language nakshatra / rashi labels (kept verbatim from `astrology.ts`).
const Map<String, String> nakshatraTamil = {
  'Ashwini': 'Ashwini (அஸ்வினி)',
  'Bharani': 'Bharani (பரணி)',
  'Krithika': 'Krithika (கார்த்திகை)',
  'Rohini': 'Rohini (ரோகிணி)',
  'Mrigashira': 'Mrigashira (மிருகசீரிடம்)',
  'Ardra': 'Thiruvadhirai (திருவாதிரை)',
  'Punarvasu': 'Punarvasu (புனர்பூசம்)',
  'Pushya': 'Pusam (பூசம்)',
  'Ashlesha': 'Ayilyam (ஆயில்யம்)',
  'Magha': 'Magam (மகம்)',
  'Purva Phalguni': 'Puram (பூரம்)',
  'Uttara Phalguni': 'Uthiram (உத்திரம்)',
  'Hasta': 'Hastham (அஸ்தம்)',
  'Chitra': 'Chithirai (சித்திரை)',
  'Swati': 'Swathi (சுவாதி)',
  'Vishakha': 'Visagam (விசாகம்)',
  'Anuradha': 'Anusham (அனுஷம்)',
  'Jyeshtha': 'Kettai (கேட்டை)',
  'Mula': 'Moolam (மூலம்)',
  'Purva Ashadha': 'Puradam (பூராடம்)',
  'Uttara Ashadha': 'Uthiradam (உத்திராடம்)',
  'Shravana': 'Thiruvonam (திருவோணம்)',
  'Dhanishta': 'Avittam (அவிட்டம்)',
  'Shatabhisha': 'Sadhayam (சதயம்)',
  'Purva Bhadrapada': 'Purattadhi (பூரட்டாதி)',
  'Uttara Bhadrapada': 'Uthirattadhi (உத்திரட்டாதி)',
  'Revati': 'Revathi (ரேவதி)',
};

const Map<String, String> rashiTamil = {
  'Mesha': 'Mesham (மேஷம்)',
  'Vrishabha': 'Rishabam (ரிஷபம்)',
  'Mithuna': 'Midhunam (மிதுனம்)',
  'Karka': 'Kadagam (கடகம்)',
  'Simha': 'Simmam (சிம்மம்)',
  'Kanya': 'Kanni (கன்னி)',
  'Tula': 'Thulam (துலாம்)',
  'Vrishchika': 'Viruchigam (விருச்சிகம்)',
  'Dhanu': 'Dhanusu (தனுசு)',
  'Makara': 'Magaram (மகரம்)',
  'Kumbha': 'Kumbam (கும்பம்)',
  'Meena': 'Meenam (மீனம்)',
};

const List<String> rasiNamesTamil = [
  'மேஷம்', 'ரிஷபம்', 'மிதுனம்', 'கடகம்',
  'சிம்மம்', 'கன்னி', 'துலாம்', 'விருச்சிகம்',
  'தனுசு', 'மகரம்', 'கும்பம்', 'மீனம்',
];

final List<String> nakshatras = nakshatraTamil.keys.toList();
final List<String> rashis = rashiTamil.keys.toList();

class PlanetMeta {
  const PlanetMeta({required this.name, required this.abbr, required this.tamil});
  final String name;
  final String abbr;
  final String tamil;
}

// Order + abbreviations match the TS `PLANETS` array.
const List<PlanetMeta> planets = [
  PlanetMeta(name: 'Sun', abbr: 'சூ', tamil: 'சூரியன்'),
  PlanetMeta(name: 'Moon', abbr: 'சந்', tamil: 'சந்திரன்'),
  PlanetMeta(name: 'Mars', abbr: 'செ', tamil: 'செவ்வாய்'),
  PlanetMeta(name: 'Mercury', abbr: 'பு', tamil: 'புதன்'),
  PlanetMeta(name: 'Jupiter', abbr: 'வி', tamil: 'குரு'),
  PlanetMeta(name: 'Venus', abbr: 'சு', tamil: 'சுக்கிரன்'),
  PlanetMeta(name: 'Saturn', abbr: 'சனி', tamil: 'சனி'),
  PlanetMeta(name: 'Rahu', abbr: 'ரா', tamil: 'ராகு'),
  PlanetMeta(name: 'Ketu', abbr: 'கே', tamil: 'கேது'),
  PlanetMeta(name: 'Lagnam', abbr: 'ல', tamil: 'லக்னம்'),
  PlanetMeta(name: 'Maandi', abbr: 'மா', tamil: 'மாந்தி'),
];

PlanetMeta? planetByName(String name) {
  for (final p in planets) {
    if (p.name == name) return p;
  }
  return null;
}

PlanetMeta? planetByAbbr(String abbr) {
  for (final p in planets) {
    if (p.abbr == abbr) return p;
  }
  return null;
}

const Map<String, String> planetTamilLabel = {
  'Suriyan': 'சூரியன்', 'Chandran': 'சந்திரன்', 'Sevvai': 'செவ்வாய்', 'Budhan': 'புதன்',
  'Guru': 'குரு', 'Sukran': 'சுக்கிரன்', 'Sani': 'சனி', 'Rahu': 'ராகு', 'Ketu': 'கேது',
  'Lagnam': 'லக்கினம்', 'Maandi': 'மாந்தி / குளிகன்',
};

double _normalize360(double v) {
  final r = v % 360.0;
  return r < 0 ? r + 360.0 : r;
}

// ---- Core math (line-for-line ports) ---------------------------------------

double _calculateJD(DateTime date) {
  // [astrology.ts: calculateJD]
  return (date.millisecondsSinceEpoch / 86400000.0) + 2440587.5;
}

double _calculateAyanamsha(double jd) {
  final t = (jd - 2415020.0) / 36525.0;
  return 22.466115 + 1.396041 * t + 0.000308 * t * t;
}

double _calculateMoon(double jd) {
  final t = (jd - 2451545.0) / 36525.0;
  final lPrime = 218.316 + 481267.881 * t;
  final d = 297.85 + 445267.111 * t;
  final m = 134.96 + 477198.868 * t;
  final lon = lPrime +
      6.289 * math.sin(m * math.pi / 180) +
      1.274 * math.sin((2 * d - m) * math.pi / 180) +
      0.658 * math.sin(2 * d * math.pi / 180);
  return _normalize360(lon);
}

double _calculateSun(double jd) {
  final t = (jd - 2451545.0) / 36525.0;
  final l0 = 280.466 + 36000.77 * t;
  final m = 357.529 + 35999.05 * t;
  final lon = l0 +
      1.915 * math.sin(m * math.pi / 180) +
      0.02 * math.sin(2 * m * math.pi / 180);
  return _normalize360(lon);
}

double _calculateLagnam(double jd, double lon, double lat) {
  final gst = 280.46061837 + 360.98564736629 * (jd - 2451545.0);
  final st = _normalize360(gst + lon);
  final obRad = 23.439 * math.pi / 180;
  final latRad = lat * math.pi / 180;
  final stRad = st * math.pi / 180;
  final asc = math.atan2(
        math.cos(stRad),
        -math.sin(stRad) * math.cos(obRad) -
            math.tan(latRad) * math.sin(obRad),
      ) *
      180 /
      math.pi;
  return _normalize360(asc);
}

int _getNavamsamIndex(double siderealLon) {
  final rasiIndex = (siderealLon / 30).floor();
  final degreesInRasi = siderealLon - rasiIndex * 30;
  final pada = (degreesInRasi / (30.0 / 9)).floor();
  if ([0, 4, 8].contains(rasiIndex)) return pada % 12;
  if ([1, 5, 9].contains(rasiIndex)) return (9 + pada) % 12;
  if ([2, 6, 10].contains(rasiIndex)) return (6 + pada) % 12;
  return (3 + pada) % 12;
}

const _dasaSequence = [
  {'name': 'Ketu', 'abbr': 'கே', 'years': 7},
  {'name': 'Venus', 'abbr': 'சு', 'years': 20},
  {'name': 'Sun', 'abbr': 'சூ', 'years': 6},
  {'name': 'Moon', 'abbr': 'சந்', 'years': 10},
  {'name': 'Mars', 'abbr': 'செ', 'years': 7},
  {'name': 'Rahu', 'abbr': 'ரா', 'years': 18},
  {'name': 'Jupiter', 'abbr': 'வி', 'years': 16},
  {'name': 'Saturn', 'abbr': 'சனி', 'years': 19},
  {'name': 'Mercury', 'abbr': 'பு', 'years': 17},
];

String _formatDdMmYyyy(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd-$mm-${d.year}';
}

List<DasaPeriod> _calculateVimshottariDasa(DateTime birth, double moonSidereal) {
  final nakLen = 360.0 / 27.0;
  final starIdx = (moonSidereal / nakLen).floor();
  final startIdx = starIdx % 9;
  final degreePassed = moonSidereal % nakLen;
  final fractionPassed = degreePassed / nakLen;
  final first = _dasaSequence[startIdx];
  final msPerYear = 365.25636 * 24 * 60 * 60 * 1000;
  var track = DateTime.fromMillisecondsSinceEpoch(
    (birth.millisecondsSinceEpoch -
            (fractionPassed * (first['years']! as int) * msPerYear))
        .round(),
  );

  final out = <DasaPeriod>[];
  for (var i = 0; i < 9; i++) {
    final dasaIdx = (startIdx + i) % 9;
    final cur = _dasaSequence[dasaIdx];
    for (var j = 0; j < 9; j++) {
      final bhIdx = (dasaIdx + j) % 9;
      final bh = _dasaSequence[bhIdx];
      final bhYears = ((cur['years']! as int) * (bh['years']! as int)) / 120.0;
      final bhMs = bhYears * msPerYear;
      final startDate = track;
      track = DateTime.fromMillisecondsSinceEpoch(
        (track.millisecondsSinceEpoch + bhMs).round(),
      );
      final endDate = track;
      if (endDate.isAfter(birth)) {
        final display = startDate.isBefore(birth) ? birth : startDate;
        out.add(DasaPeriod(
          dasa: cur['abbr']! as String,
          bhukti: bh['abbr']! as String,
          start: _formatDdMmYyyy(display),
          end: _formatDdMmYyyy(endDate),
          endMs: endDate.millisecondsSinceEpoch,
        ));
      }
    }
  }
  return out;
}

PapaPulligal _calculatePapaPulligal(List<PlanetPosition> planetsList) {
  final lagnaPlanet = planetsList.firstWhere((p) => p.isLagnam,
      orElse: () => planetsList.first);
  final moonPlanet = planetsList.firstWhere((p) => p.name == 'Moon',
      orElse: () => planetsList.first);
  final venusPlanet = planetsList.firstWhere((p) => p.name == 'Venus',
      orElse: () => planetsList.first);
  final lagna = lagnaPlanet.rasiIndex;
  final moonRasi = moonPlanet.rasiIndex;
  final venusRasi = venusPlanet.rasiIndex;

  int getRelativeHouse(int planetRasi, int refRasi) =>
      ((planetRasi - refRasi + 12) % 12) + 1;

  const doshaHouses = [1, 2, 4, 7, 8, 12];
  const targets = ['Mars', 'Saturn', 'Sun', 'Rahu'];
  const tamilNames = {
    'Mars': 'செவ்வாய்',
    'Saturn': 'சனி',
    'Sun': 'சூரியன்',
    'Rahu': 'ராகு',
  };

  final rows = <PapaPulligalRow>[];
  var totalP1 = 0.0;
  var totalP2 = 0.0;
  var totalP3 = 0.0;

  for (final t in targets) {
    final pl =
        planetsList.where((p) => p.name == t).cast<PlanetPosition?>().firstWhere(
              (p) => true,
              orElse: () => null,
            );
    if (pl == null) continue;
    final prasi = pl.rasiIndex;
    final v1 = getRelativeHouse(prasi, lagna);
    final p1 = doshaHouses.contains(v1) ? 1.0 : 0.0;
    final v2 = getRelativeHouse(prasi, moonRasi);
    final p2 = doshaHouses.contains(v2) ? 1.0 : 0.0;
    final v3 = getRelativeHouse(prasi, venusRasi);
    final p3 = doshaHouses.contains(v3) ? 1.0 : 0.0;
    totalP1 += p1;
    totalP2 += p2;
    totalP3 += p3;
    rows.add(PapaPulligalRow(
      planet: tamilNames[t]!,
      v1: v1,
      p1: p1.toStringAsFixed(1),
      v2: v2,
      p2: p2.toStringAsFixed(1),
      v3: v3,
      p3: p3.toStringAsFixed(1),
    ));
  }

  String dosha(PapaPulligalRow r) {
    final sum = double.parse(r.p1) + double.parse(r.p2) + double.parse(r.p3);
    return sum > 1 ? 'தோஷம் உள்ளது' : 'தோஷம் இல்லை';
  }

  return PapaPulligal(
    rows: rows,
    totalP1: totalP1.toStringAsFixed(1),
    totalP2: totalP2.toStringAsFixed(1),
    totalP3: totalP3.toStringAsFixed(1),
    sevvaiDosham: rows.isNotEmpty ? dosha(rows[0]) : 'தோஷம் இல்லை',
    rahuDosham: rows.length >= 4 ? dosha(rows[3]) : 'தோஷம் இல்லை',
  );
}

const _yogaNames = [
  'Vishkumbha', 'Preeti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda',
  'Sukarma', 'Dhriti', 'Shoola', 'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata',
  'Harshana', 'Vajra', 'Siddhi', 'Vyatipata', 'Variyan', 'Parigha', 'Shiva',
  'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma', 'Indra', 'Vaidhriti',
];

const Map<String, String> _planetAbbrMap = {
  'Sun': 'சூ',
  'Moon': 'சந்',
  'Mercury': 'பு',
  'Venus': 'சு',
  'Mars': 'செ',
  'Jupiter': 'வி',
  'Saturn': 'சனி',
  'Rahu': 'ரா',
  'Ketu': 'கே',
};

const Map<String, String> _planetTamilMap = {
  'Sun': 'Suriyan',
  'Moon': 'Chandran',
  'Mercury': 'Budhan',
  'Venus': 'Sukran',
  'Mars': 'Sevvai',
  'Jupiter': 'Guru',
  'Saturn': 'Sani',
  'Rahu': 'Rahu',
  'Ketu': 'Ketu',
};

/// Synchronous mean-motion port of `generateHoroscope` from `lib/astrology.ts`.
/// Returns the same shape the web's `DetailedHoroscopeView` consumes.
HoroscopeDetails generateHoroscope({
  required DateTime birthLocalDate,
  required Location location,
  Duration timezoneOffset = const Duration(hours: 5, minutes: 30),
  String method = 'thirukanitham',
}) {
  // [astrology.ts:160] — Compute the Date object the same way: local clock
  // string + IANA-equivalent fixed timezone offset.
  final utcDate = birthLocalDate.toUtc().subtract(timezoneOffset).add(
        Duration(milliseconds: birthLocalDate.millisecondsSinceEpoch -
            DateTime(
              birthLocalDate.year,
              birthLocalDate.month,
              birthLocalDate.day,
              birthLocalDate.hour,
              birthLocalDate.minute,
              birthLocalDate.second,
              birthLocalDate.millisecond,
            ).millisecondsSinceEpoch),
      );
  final date = DateTime.fromMillisecondsSinceEpoch(
    DateTime(
      birthLocalDate.year,
      birthLocalDate.month,
      birthLocalDate.day,
      birthLocalDate.hour,
      birthLocalDate.minute,
      birthLocalDate.second,
      birthLocalDate.millisecond,
    ).millisecondsSinceEpoch -
        timezoneOffset.inMilliseconds,
    isUtc: true,
  );
  // (utcDate is unused beyond proving the conversion is well-defined; we use
  // `date` for everything below — same as the TS code computing one `Date`.)
  // ignore: unused_local_variable
  final _ = utcDate;

  final jd = _calculateJD(date);
  var ayan = _calculateAyanamsha(jd);
  if (method == 'vakkiyam') ayan -= 1.283;

  final t = (jd - 2451545.0) / 36525;

  // Mean-motion fallback positions (line-for-line port of the TS fallback).
  final tropicalSun = _calculateSun(jd);
  final tropicalMoon = _calculateMoon(jd);
  final fallback = {
    'Sun': _normalize360(tropicalSun - ayan),
    'Mercury': _normalize360((252.25 + 149472.93 * t) - ayan),
    'Venus': _normalize360((181.97 + 58517.81 * t) - ayan),
    'Mars': _normalize360((355.45 + 19140.3 * t) - ayan),
    'Jupiter': _normalize360((34.35 + 3034.9 * t) - ayan),
    'Saturn': _normalize360((49.95 + 1222.11 * t) - ayan),
    'Rahu': _normalize360((125.04 - 1934.13 * t) - ayan),
    'Ketu': _normalize360((125.04 - 1934.13 * t + 180) - ayan),
  };

  final siderealMoon = _normalize360(tropicalMoon - ayan).abs() % 360.0;
  final trueSunSidereal = fallback['Sun']!;

  final raw = <Map<String, dynamic>>[
    {'name': 'Sun', 'tamil': 'Suriyan', 'abbr': 'சூ', 'sidLon': trueSunSidereal},
    {'name': 'Moon', 'tamil': 'Chandran', 'abbr': 'சந்', 'sidLon': siderealMoon},
    {'name': 'Mercury', 'tamil': 'Budhan', 'abbr': 'பு', 'sidLon': fallback['Mercury']},
    {'name': 'Venus', 'tamil': 'Sukran', 'abbr': 'சு', 'sidLon': fallback['Venus']},
    {'name': 'Mars', 'tamil': 'Sevvai', 'abbr': 'செ', 'sidLon': fallback['Mars']},
    {'name': 'Jupiter', 'tamil': 'Guru', 'abbr': 'வி', 'sidLon': fallback['Jupiter']},
    {'name': 'Saturn', 'tamil': 'Sani', 'abbr': 'சனி', 'sidLon': fallback['Saturn']},
    {'name': 'Rahu', 'tamil': 'Rahu', 'abbr': 'ரா', 'sidLon': fallback['Rahu']},
    {'name': 'Ketu', 'tamil': 'Ketu', 'abbr': 'கே', 'sidLon': fallback['Ketu']},
    {
      'name': 'Lagnam',
      'tamil': 'Lagnam',
      'abbr': 'ல',
      'sidLon': _normalize360(_calculateLagnam(jd, location.longitude, location.latitude) - ayan),
      'isLagnam': true,
    },
    {
      'name': 'Maandi',
      'tamil': 'Maandi',
      'abbr': 'மா',
      'sidLon': _normalize360(trueSunSidereal + 90),
    },
  ];

  final out = <PlanetPosition>[];
  for (final r in raw) {
    final sid = (r['sidLon'] as num).toDouble();
    out.add(PlanetPosition(
      name: r['name'] as String,
      tamilName: r['tamil'] as String,
      tamilAbbr: r['abbr'] as String,
      longitude: _normalize360(sid + ayan),
      siderealLongitude: sid,
      rasiIndex: (sid / 30).floor() % 12,
      navamsamIndex: _getNavamsamIndex(sid),
      isLagnam: r['isLagnam'] == true,
    ));
  }

  final moon = out.firstWhere((p) => p.name == 'Moon');
  final sun = out.firstWhere((p) => p.name == 'Sun');
  final lag = out.firstWhere((p) => p.isLagnam);

  final starIdx = (moon.siderealLongitude / (360 / 27)).floor() % 27;
  final elong = _normalize360(moon.siderealLongitude - sun.siderealLongitude);
  final tithiIdx = (elong / 12).floor();
  final yogaIdx = ((moon.siderealLongitude + sun.siderealLongitude) % 360 / (360 / 27))
      .floor()
      .clamp(0, _yogaNames.length - 1);

  final starName = nakshatras[starIdx];
  final rasiName = rashis[moon.rasiIndex % 12];
  final lagName = rashis[lag.rasiIndex % 12];

  return HoroscopeDetails(
    star: nakshatraTamil[starName] ?? starName,
    rashi: rashiTamil[rasiName] ?? rasiName,
    lagnam: rashiTamil[lagName] ?? lagName,
    yoga: _yogaNames[yogaIdx],
    karana: 'N/A',
    sunrise: '6:12 AM',
    sunset: '6:24 PM',
    planets: out,
    nakshatraIndex: starIdx,
    tithiIndex: tithiIdx,
    dasaPeriods: _calculateVimshottariDasa(date, moon.siderealLongitude),
    papaPulligal: _calculatePapaPulligal(out),
    calculationMethod: method,
  );
}

/// Build a "manual chart" stub (web `handleGenerate` sets a dummy result
/// with `isManual: true`). Lagnam house may be supplied so the chart shows
/// the lagna marker in the right rasi.
HoroscopeDetails buildManualHoroscope({String? lagnamHouseLabel}) {
  return HoroscopeDetails(
    star: 'Manual Entry',
    rashi: 'Custom Chart',
    lagnam: lagnamHouseLabel ?? 'Manual',
    yoga: '—',
    karana: '—',
    sunrise: '',
    sunset: '',
    planets: const [],
    nakshatraIndex: 0,
    tithiIndex: 0,
    dasaPeriods: const [],
    papaPulligal: null,
    calculationMethod: 'manual',
    isManual: true,
  );
}

String formatSputam(double deg) {
  final d = deg.floor();
  final m = ((deg - d) * 60).floor();
  final s = (((deg - d) * 60 - m) * 60).floor();
  return '$d:$m:$s';
}

String planetTamilFull(PlanetPosition p) {
  final key = _planetTamilMap[p.name] ?? p.tamilName;
  return planetTamilLabel[key] ?? key;
}

String planetAbbrFor(String name) => _planetAbbrMap[name] ?? '';
