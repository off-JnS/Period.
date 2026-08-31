import 'package:period/data/system_clock.dart';
import 'package:period/domain/models/clock.dart';
import 'package:test/test.dart';

import '../support/dates.dart';
import '../support/fixed_clock.dart';

void main() {
  group('FixedClock', () {
    test('reports the day it was frozen at', () {
      final clock = FixedClock(aDate(2024, 5, 17));
      expect(clock.today(), aDate(2024, 5, 17));
    });

    test('reports the same day however often it is asked', () {
      final clock = FixedClock(aDate(2024, 5, 17));
      expect(clock.today(), clock.today());
    });

    test('can be walked forward without rebuilding its dependents', () {
      final clock = FixedClock(aDate(2024, 12, 31));
      expect(clock.today(), aDate(2024, 12, 31));

      clock.date = clock.date.addDays(1);
      expect(clock.today(), aDate(2025, 1, 1));
    });

    test('is a Clock, so logic can take the abstraction', () {
      final Clock clock = FixedClock(anyDate());
      expect(clock.today(), anyDate());
    });
  });

  group('SystemClock', () {
    test('reports the device calendar day, with no time attached', () {
      // The one place the real clock is read. Sampling twice guards against the
      // rare case of the day rolling over between the two reads.
      final before = DateTime.now();
      final today = const SystemClock().today();
      final after = DateTime.now();

      final candidates = {
        (before.year, before.month, before.day),
        (after.year, after.month, after.day),
      };
      expect(candidates, contains((today.year, today.month, today.day)));
    });

    test('is const constructible, so it can be shared', () {
      expect(const SystemClock(), isA<Clock>());
    });
  });
}
