import 'dart:math' as math;

/// Mirrors [manavizha/lib/utils/match-utils.ts] for deterministic daily ordering.
String getDailySeed(String userId) {
  final today = DateTime.now().toIso8601String().split('T').first;
  return '$today-$userId';
}

/// Fisher–Yates shuffle with the same seeded PRNG as the web app (`Math.sin`).
List<T> seededShuffle<T>(List<T> arr, String seedStr) {
  final result = List<T>.from(arr);
  var seed = 0;
  for (final code in seedStr.codeUnits) {
    seed += code;
  }
  var s = seed;
  for (var i = result.length - 1; i > 0; i--) {
    final x = math.sin(s++) * 10000;
    final random = x - x.floorToDouble();
    final j = (random * (i + 1)).floor();
    final tmp = result[i];
    result[i] = result[j];
    result[j] = tmp;
  }
  return result;
}
