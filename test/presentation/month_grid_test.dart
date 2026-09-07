import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/calendar/month_grid.dart';

import '../support/dates.dart';

void main() {
  group('layout', () {
    test('starts on the locale first weekday', () {
      // 1 May 2024 is a Wednesday. Starting the week on Monday means two
      // padding days before it.
      final monday = MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 1);
      expect(monday.days.first, aDate(2024, 4, 29));

      // Starting on Sunday means three.
      final sunday = MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 7);
      expect(sunday.days.first, aDate(2024, 4, 28));
    });

    test('is always whole weeks', () {
      for (var month = 1; month <= 12; month++) {
        for (final first in [1, 7]) {
          final grid = MonthGrid.of(aDate(2024, month, 1), firstWeekday: first);
          expect(grid.days.length % 7, 0, reason: 'month $month, first $first');
          expect(grid.weeks.every((week) => week.length == 7), isTrue);
        }
      }
    });

    test('contains every day of the month', () {
      final grid = MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 1);
      final inMonth = grid.days.where(grid.isInMonth).toList();
      expect(inMonth, hasLength(31));
      expect(inMonth.first, aDate(2024, 5, 1));
      expect(inMonth.last, aDate(2024, 5, 31));
    });

    test('days run consecutively with no gaps', () {
      final grid = MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 1);
      for (var i = 1; i < grid.days.length; i++) {
        expect(
          grid.days[i - 1].addDays(1),
          grid.days[i],
          reason: 'gap at index $i',
        );
      }
    });

    test('handles a leap February', () {
      final grid = MonthGrid.of(aDate(2024, 2, 1), firstWeekday: 1);
      expect(grid.days.where(grid.isInMonth), hasLength(29));
    });

    test('handles a common February', () {
      final grid = MonthGrid.of(aDate(2023, 2, 1), firstWeekday: 1);
      expect(grid.days.where(grid.isInMonth), hasLength(28));
    });

    test('a month starting exactly on the first weekday has no lead', () {
      // 1 April 2024 is a Monday.
      final grid = MonthGrid.of(aDate(2024, 4, 1), firstWeekday: 1);
      expect(grid.days.first, aDate(2024, 4, 1));
    });

    test('any day of the month gives the same grid as the first', () {
      expect(
        MonthGrid.of(aDate(2024, 5, 17), firstWeekday: 1).days,
        MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 1).days,
      );
    });

    test('rejects a nonsense first weekday', () {
      expect(
        () => MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 0),
        throwsArgumentError,
      );
      expect(
        () => MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 8),
        throwsArgumentError,
      );
    });
  });

  group('moving between months', () {
    test('previous crosses a year boundary', () {
      final january = MonthGrid.of(aDate(2024, 1, 15), firstWeekday: 1);
      expect(january.previous().month, aDate(2023, 12, 1));
    });

    test('next crosses a year boundary', () {
      final december = MonthGrid.of(aDate(2024, 12, 15), firstWeekday: 1);
      expect(december.next().month, aDate(2025, 1, 1));
    });

    test('next from a 31-day month lands on the 1st', () {
      // The arithmetic adds the month's own length, so it cannot overshoot into
      // the month after next the way "add 31 days" would from February.
      for (var month = 1; month <= 12; month++) {
        final grid = MonthGrid.of(aDate(2024, month, 1), firstWeekday: 1);
        final next = grid.next();
        expect(next.month.day, 1, reason: 'from month $month');
        expect(
          next.month.month,
          month == 12 ? 1 : month + 1,
          reason: 'from month $month',
        );
      }
    });

    test('there and back returns to the same month', () {
      final may = MonthGrid.of(aDate(2024, 5, 1), firstWeekday: 1);
      expect(may.next().previous().month, may.month);
    });
  });
}
