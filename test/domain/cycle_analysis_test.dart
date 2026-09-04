import 'package:period/domain/logic/cycle_analysis.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  group('cyclesFrom', () {
    test('no period starts means no cycles', () {
      expect(cyclesFrom(const []), isEmpty);
    });

    test('one period start is one cycle, still in progress', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1)]);
      expect(cycles, hasLength(1));
      expect(cycles.single.isInProgress, isTrue);
      expect(cycles.single.lengthInDays, isNull);
    });

    test('a cycle ends the day before the next one starts', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 1, 29)]);
      expect(cycles.first.end, aDate(2024, 1, 28));
      expect(
        cycles.first.lengthInDays,
        28,
        reason: '1 Jan to 29 Jan is 28 days',
      );
    });

    test('only the most recent cycle is in progress', () {
      final cycles = cyclesFrom([
        aDate(2024, 1, 1),
        aDate(2024, 1, 29),
        aDate(2024, 2, 26),
      ]);
      expect(cycles.map((c) => c.isInProgress), [false, false, true]);
    });

    test('accepts starts logged out of order', () {
      final cycles = cyclesFrom([
        aDate(2024, 2, 26),
        aDate(2024, 1, 1),
        aDate(2024, 1, 29),
      ]);
      expect(cycles.map((c) => c.start), [
        aDate(2024, 1, 1),
        aDate(2024, 1, 29),
        aDate(2024, 2, 26),
      ]);
    });

    test('a day marked twice counts once', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 1, 1)]);
      expect(cycles, hasLength(1));
    });

    test('spans a year boundary correctly', () {
      final cycles = cyclesFrom([aDate(2023, 12, 15), aDate(2024, 1, 12)]);
      expect(cycles.first.lengthInDays, 28);
    });

    test('counts a leap day', () {
      final cycles = cyclesFrom([aDate(2024, 2, 1), aDate(2024, 3, 1)]);
      expect(
        cycles.first.lengthInDays,
        29,
        reason: '2024 February has 29 days',
      );
    });
  });

  group('eligibleForStatistics', () {
    test('drops the in-progress cycle', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 1, 29)]);
      expect(eligibleForStatistics(cycles), hasLength(1));
    });

    test('keeps a 21-day cycle', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 1, 22)]);
      expect(eligibleForStatistics(cycles).single.lengthInDays, 21);
    });

    test('keeps a 40-day cycle', () {
      // Unusual, but a real person. Section 2 of docs/cycle-logic.md: exclusion
      // is for logging artifacts, never for unusual bodies.
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 2, 10)]);
      expect(eligibleForStatistics(cycles).single.lengthInDays, 40);
    });

    test('keeps a three-month gap if it is under the artifact threshold', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 3, 25)]);
      expect(eligibleForStatistics(cycles), hasLength(1));
    });

    test('drops a cycle longer than 90 days as a missed start', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 5, 1)]);
      expect(eligibleForStatistics(cycles), isEmpty);
    });

    test('drops a cycle shorter than 10 days as a double-logged start', () {
      final cycles = cyclesFrom([aDate(2024, 1, 1), aDate(2024, 1, 5)]);
      expect(eligibleForStatistics(cycles), isEmpty);
    });

    test('keeps exactly the boundary lengths', () {
      expect(
        eligibleForStatistics(
          cyclesFrom([aDate(2024, 1, 1), aDate(2024, 1, 11)]),
        ).single.lengthInDays,
        shortestPlausibleCycle,
      );
      expect(
        eligibleForStatistics(
          cyclesFrom([aDate(2024, 1, 1), aDate(2024, 3, 31)]),
        ).single.lengthInDays,
        longestPlausibleCycle,
      );
    });

    test('keeps only the most recent six', () {
      var day = aDate(2020, 1, 1);
      final starts = [day];
      for (var i = 0; i < 10; i++) {
        day = day.addDays(28);
        starts.add(day);
      }
      final eligible = eligibleForStatistics(cyclesFrom(starts));

      expect(eligible, hasLength(statisticsWindow));
      expect(
        eligible.last.end,
        starts.last.subtractDays(1),
        reason: 'the newest completed cycle must be included',
      );
    });

    test('an artifact does not consume one of the six slots', () {
      // The bad cycle is filtered before the window is taken, so a single
      // mis-logged start does not cost the user a real cycle of history.
      var day = aDate(2020, 1, 1);
      final starts = [day];
      for (var i = 0; i < 7; i++) {
        day = day.addDays(28);
        starts.add(day);
      }
      starts.add(day.addDays(3)); // a double-logged start: a 3-day "cycle"

      final eligible = eligibleForStatistics(cyclesFrom(starts));
      expect(eligible, hasLength(statisticsWindow));
      expect(eligible.every((c) => c.lengthInDays == 28), isTrue);
    });
  });

  group('cycleDayOn', () {
    test('is null when nothing has been logged', () {
      expect(cycleDayOn(aDate(2024, 1, 15), const []), isNull);
    });

    test('the period start itself is day 1', () {
      expect(cycleDayOn(aDate(2024, 1, 1), [aDate(2024, 1, 1)]), 1);
    });

    test('counts forward from the most recent start', () {
      expect(cycleDayOn(aDate(2024, 1, 15), [aDate(2024, 1, 1)]), 15);
    });

    test('restarts at the next period', () {
      final starts = [aDate(2024, 1, 1), aDate(2024, 1, 29)];
      expect(cycleDayOn(aDate(2024, 1, 28), starts), 28);
      expect(cycleDayOn(aDate(2024, 1, 29), starts), 1);
      expect(cycleDayOn(aDate(2024, 1, 30), starts), 2);
    });

    test('is null before the first recorded start', () {
      // Not day zero -- outside the data entirely.
      expect(cycleDayOn(aDate(2023, 12, 31), [aDate(2024, 1, 1)]), isNull);
    });

    test('keeps counting past the expected length', () {
      // A late period does not reset the count or stop it.
      expect(cycleDayOn(aDate(2024, 3, 1), [aDate(2024, 1, 1)]), 61);
    });

    test('ignores starts logged out of order', () {
      final starts = [aDate(2024, 1, 29), aDate(2024, 1, 1)];
      expect(cycleDayOn(aDate(2024, 1, 30), starts), 2);
    });

    test('spans a year boundary', () {
      expect(cycleDayOn(aDate(2024, 1, 5), [aDate(2023, 12, 29)]), 8);
    });
  });
}
