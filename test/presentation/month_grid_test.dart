import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/calendar/month_grid.dart';

import '../support/dates.dart';

/// The grid is pure date arithmetic, so it is tested as arithmetic: no widgets,
/// no locale objects, just which days land in which cells.
void main() {
  /// Monday-first, as in German.
  const monday = 1;

  /// Sunday-first, as in American English.
  const sunday = 0;

  group('shape', () {
    test('is always whole weeks', () {
      for (var month = 1; month <= 12; month++) {
        final grid = monthGrid(
          year: 2024,
          month: month,
          firstDayOfWeekIndex: monday,
        );
        expect(
          grid.days.length % 7,
          0,
          reason: 'month $month is not a whole number of weeks',
        );
      }
    });

    test('covers every day of the month exactly once', () {
      final grid = monthGrid(year: 2024, month: 5, firstDayOfWeekIndex: monday);
      final inMonth = grid.days.where(grid.isInMonth).toList();
      expect(inMonth.length, 31);
      expect(inMonth.first, aDate(2024, 5, 1));
      expect(inMonth.last, aDate(2024, 5, 31));
    });

    test('runs in unbroken single-day steps', () {
      // The property that matters: no repeated and no skipped day. A grid built
      // with Duration across a clock change fails exactly here.
      final grid = monthGrid(year: 2024, month: 3, firstDayOfWeekIndex: monday);
      for (var i = 1; i < grid.days.length; i++) {
        expect(grid.days[i - 1].daysUntil(grid.days[i]), 1);
      }
    });

    test('splits into rows of seven', () {
      final grid = monthGrid(year: 2024, month: 5, firstDayOfWeekIndex: monday);
      expect(grid.weeks.every((week) => week.length == 7), isTrue);
      expect(grid.weeks.length * 7, grid.days.length);
    });
  });

  group('where the week starts', () {
    test('Monday-first begins each row on a Monday', () {
      final grid = monthGrid(year: 2024, month: 5, firstDayOfWeekIndex: monday);
      expect(grid.days.first.weekday, 1);
      for (final week in grid.weeks) {
        expect(week.first.weekday, 1);
      }
    });

    test('Sunday-first begins each row on a Sunday', () {
      final grid = monthGrid(year: 2024, month: 5, firstDayOfWeekIndex: sunday);
      // ISO 7 is Sunday.
      expect(grid.days.first.weekday, 7);
      for (final week in grid.weeks) {
        expect(week.first.weekday, 7);
      }
    });

    test('the two layouts disagree, which is the point', () {
      final de = monthGrid(year: 2024, month: 9, firstDayOfWeekIndex: monday);
      final us = monthGrid(year: 2024, month: 9, firstDayOfWeekIndex: sunday);
      expect(de.days.first, isNot(us.days.first));
    });
  });

  group('awkward months', () {
    test(
      'a month starting exactly on the first day of the week has no lead',
      () {
        // April 2024 begins on a Monday.
        final grid = monthGrid(
          year: 2024,
          month: 4,
          firstDayOfWeekIndex: monday,
        );
        expect(grid.days.first, aDate(2024, 4, 1));
      },
    );

    test('February in a leap year ends on the 29th', () {
      final grid = monthGrid(year: 2024, month: 2, firstDayOfWeekIndex: monday);
      final inMonth = grid.days.where(grid.isInMonth).toList();
      expect(inMonth.length, 29);
      expect(inMonth.last, aDate(2024, 2, 29));
    });

    test('February in a common year ends on the 28th', () {
      final grid = monthGrid(year: 2023, month: 2, firstDayOfWeekIndex: monday);
      final inMonth = grid.days.where(grid.isInMonth).toList();
      expect(inMonth.length, 28);
      expect(inMonth.last, aDate(2023, 2, 28));
    });

    test('February 2021 begins on the first day of a Monday-first week', () {
      // 1 Feb 2021 was a Monday, so the grid is exactly four weeks with no
      // padding at either end -- the one case where a grid can be 28 cells.
      final grid = monthGrid(year: 2021, month: 2, firstDayOfWeekIndex: monday);
      expect(grid.days.length, 28);
      expect(grid.days.every(grid.isInMonth), isTrue);
    });

    test('crosses a year boundary in both directions', () {
      // 2025 rather than 2024: 1 January 2024 was itself a Monday, so a
      // Monday-first grid for it has no lead at all and would prove nothing.
      final january = monthGrid(
        year: 2025,
        month: 1,
        firstDayOfWeekIndex: monday,
      );
      expect(january.days.first.year, 2024);
      expect(january.isInMonth(january.days.first), isFalse);

      final december = monthGrid(
        year: 2024,
        month: 12,
        firstDayOfWeekIndex: monday,
      );
      expect(december.days.last.year, 2025);
      expect(december.isInMonth(december.days.last), isFalse);
    });

    test('a 31-day month needing six rows gets six', () {
      // December 2024 starts on a Sunday, so Monday-first needs six weeks.
      final grid = monthGrid(
        year: 2024,
        month: 12,
        firstDayOfWeekIndex: monday,
      );
      expect(grid.weeks.length, 6);
    });
  });
}
