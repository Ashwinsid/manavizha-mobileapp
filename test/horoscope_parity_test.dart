import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manavizha_app/astrology.dart' as astro;

/// Horoscope engine parity test.
///
/// `test/horoscope_web_vectors.json` is the output of the WEB engine
/// (`manavizha/lib/astrology.ts::generateHoroscope`) executed on fixed birth
/// data. The Dart engine must produce the same star, rashi, lagnam, per-planet
/// rasi/navamsam placement and sidereal longitudes — proving both apps render
/// identical horoscopes and porutham inputs for the same member.
void main() {
  final vectors = jsonDecode(
    File('test/horoscope_web_vectors.json').readAsStringSync(),
  ) as List<dynamic>;

  for (final raw in vectors) {
    final v = Map<String, dynamic>.from(raw as Map);
    final input = Map<String, dynamic>.from(v['input'] as Map);
    final dt = DateTime.parse(input['dt'] as String);
    final method = input['method'] as String;

    test('matches web engine for ${input['dt']} ($method)', () {
      final h = astro.generateHoroscope(
        birthLocalDate: dt,
        location: astro.Location(
          latitude: (input['lat'] as num).toDouble(),
          longitude: (input['lon'] as num).toDouble(),
        ),
        timezoneOffset: const Duration(hours: 5, minutes: 30),
        method: method,
      );

      expect(h.star, equals(v['star']), reason: 'star');
      expect(h.rashi, equals(v['rashi']), reason: 'rashi');
      expect(h.lagnam, equals(v['lagnam']), reason: 'lagnam');

      final webPlanets = (v['planets'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      for (final wp in webPlanets) {
        final name = wp['name'] as String;
        final dp = h.planets.where((p) => p.name == name).toList();
        expect(dp, isNotEmpty, reason: 'planet $name missing in Dart output');
        expect(dp.first.rasiIndex, equals(wp['rasiIndex']),
            reason: '$name rasiIndex');
        expect(dp.first.navamsamIndex, equals(wp['navamsamIndex']),
            reason: '$name navamsamIndex');
        expect(
          dp.first.siderealLongitude,
          closeTo((wp['sid'] as num).toDouble(), 1e-4),
          reason: '$name siderealLongitude',
        );
      }

      final webDasa = v['firstDasa'];
      if (webDasa is Map && h.dasaPeriods.isNotEmpty) {
        final first = h.dasaPeriods.first;
        expect(first.dasa, equals(webDasa['dasa']), reason: 'first dasa');
        expect(first.bhukti, equals(webDasa['bhukti']), reason: 'first bhukti');
        expect(first.start, equals(webDasa['start']), reason: 'dasa start');
        expect(first.end, equals(webDasa['end']), reason: 'dasa end');
      }
    });
  }
}
