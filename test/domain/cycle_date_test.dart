import 'package:period/domain/models/cycle_date.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  group('construction', () {
    test('rejects a month outside 1..12', () {
      expect(() => CycleDate(2024, 0, 1), throwsArgumentError);
      expect(() => CycleDate(2024, 13, 1), throwsArgumentError);
      expect(() => CycleDate(2024, -1, 1), throwsArgumentError);
    });

    test('rejects a day outside the real length of the month', () {
      expect(() => CycleDate(2024, 1, 0), throwsArgumentError);
      expect(() => CycleDate(2024, 1, 32), throwsArgumentError);
      expect(
        () => CycleDate(2024, 4, 31),
        throwsArgumentError,
        reason: 'April has 30 days',
      );
    });

    test(
      'rejects 29 February in a common year but allows it in a leap year',
      () {
        expect(() => CycleDate(2023, 2, 29), throwsArgumentError);
        expect(aDate(2024, 2, 29).day, 29);
      },
    );

    test('does not silently normalise an impossible date into a real one', () {
      // Normalising 2023-02-29 to 2023-03-01 would move a logged entry to a day
      // the user did not choose. It must throw instead.
      expect(() => CycleDate(2023, 2, 29), throwsArgumentError);
    });
  });

  group('leap years', () {
    test('applies the century rule', () {
      expect(CycleDate.isLeapYear(1900), isFalse);
      expect(CycleDate.isLeapYear(2000), isTrue);
      expect(CycleDate.isLeapYear(2100), isFalse);
      expect(CycleDate.isLeapYear(2024), isTrue);
      expect(CycleDate.isLeapYear(2023), isFalse);
    });

    test('February length follows it', () {
      expect(CycleDate.lastDayOfMonth(1900, 2), 28);
      expect(CycleDate.lastDayOfMonth(2000, 2), 29);
      expect(CycleDate.lastDayOfMonth(2024, 2), 29);
      expect(CycleDate.lastDayOfMonth(2023, 2), 28);
    });

    test('other month lengths are constant', () {
      expect(CycleDate.lastDayOfMonth(2024, 1), 31);
      expect(CycleDate.lastDayOfMonth(2024, 4), 30);
      expect(CycleDate.lastDayOfMonth(2024, 12), 31);
    });
  });

  group('addDays', () {
    test('zero returns the same day', () {
      expect(aDate(2024, 5, 17).addDays(0), aDate(2024, 5, 17));
    });

    test('crosses a month end', () {
      expect(aDate(2024, 1, 31).addDays(1), aDate(2024, 2, 1));
      expect(aDate(2024, 4, 30).addDays(1), aDate(2024, 5, 1));
    });

    test('crosses a year end in both directions', () {
      expect(aDate(2023, 12, 31).addDays(1), aDate(2024, 1, 1));
      expect(aDate(2024, 1, 1).subtractDays(1), aDate(2023, 12, 31));
    });

    test('crosses 28 February differently in a leap and a common year', () {
      expect(aDate(2024, 2, 28).addDays(1), aDate(2024, 2, 29));
      expect(aDate(2023, 2, 28).addDays(1), aDate(2023, 3, 1));
    });

    test('spans a whole common year and a whole leap year', () {
      expect(aDate(2023, 1, 1).addDays(365), aDate(2024, 1, 1));
      expect(aDate(2024, 1, 1).addDays(366), aDate(2025, 1, 1));
    });

    test('handles large negative offsets', () {
      expect(aDate(2024, 5, 17).addDays(-1000), aDate(2021, 8, 21));
    });

    test('round-trips for a range of offsets', () {
      final start = aDate(2024, 2, 29);
      for (var n = -400; n <= 400; n += 7) {
        expect(
          start.addDays(n).addDays(-n),
          start,
          reason: 'offset $n did not round-trip',
        );
      }
    });

    test('advances exactly one calendar day across a clock change', () {
      // Europe/Berlin springs forward on 2024-03-31 and falls back on
      // 2024-10-27. Those days are 23 and 25 hours long, so Duration(days: 1)
      // arithmetic on a local DateTime lands on the wrong calendar day. These
      // dates are named here so that a future rewrite onto Duration fails loudly
      // instead of silently shifting a user's entries.
      expect(aDate(2024, 3, 31).addDays(1), aDate(2024, 4, 1));
      expect(aDate(2024, 3, 30).addDays(2), aDate(2024, 4, 1));
      expect(aDate(2024, 10, 27).addDays(1), aDate(2024, 10, 28));
      expect(aDate(2024, 10, 26).addDays(2), aDate(2024, 10, 28));

      // The US changes on different days again; a cycle spanning either must
      // still be counted in whole days.
      expect(aDate(2024, 3, 10).addDays(1), aDate(2024, 3, 11));
      expect(aDate(2024, 11, 3).addDays(1), aDate(2024, 11, 4));
    });

    test('stepping day by day matches one large jump', () {
      var stepped = aDate(2023, 11, 15);
      for (var i = 0; i < 200; i++) {
        stepped = stepped.addDays(1);
      }
      expect(stepped, aDate(2023, 11, 15).addDays(200));
    });
  });

  group('daysUntil', () {
    test('is zero for the same day', () {
      expect(aDate(2024, 5, 17).daysUntil(aDate(2024, 5, 17)), 0);
    });

    test('is positive forwards and negative backwards', () {
      expect(aDate(2024, 5, 1).daysUntil(aDate(2024, 5, 29)), 28);
      expect(aDate(2024, 5, 29).daysUntil(aDate(2024, 5, 1)), -28);
    });

    test('is antisymmetric', () {
      final a = aDate(2021, 3, 14);
      final b = aDate(2024, 9, 2);
      expect(a.daysUntil(b), -b.daysUntil(a));
    });

    test('counts the leap day', () {
      expect(aDate(2024, 2, 28).daysUntil(aDate(2024, 3, 1)), 2);
      expect(aDate(2023, 2, 28).daysUntil(aDate(2023, 3, 1)), 1);
    });

    test('agrees with addDays', () {
      final from = aDate(2022, 7, 30);
      final to = aDate(2023, 1, 2);
      expect(from.addDays(from.daysUntil(to)), to);
    });
  });

  group('ordering and equality', () {
    test('equal values are equal and share a hash code', () {
      expect(aDate(2024, 5, 17), aDate(2024, 5, 17));
      expect(aDate(2024, 5, 17).hashCode, aDate(2024, 5, 17).hashCode);
    });

    test('different values are not equal', () {
      expect(aDate(2024, 5, 17), isNot(aDate(2024, 5, 18)));
      expect(aDate(2024, 5, 17), isNot(aDate(2024, 6, 17)));
      expect(aDate(2024, 5, 17), isNot(aDate(2025, 5, 17)));
    });

    test('works as a Set member and a Map key', () {
      final seen = {aDate(2024, 5, 17), aDate(2024, 5, 17)};
      expect(seen, hasLength(1));

      final byDay = {aDate(2024, 5, 17): 'logged'};
      expect(byDay[aDate(2024, 5, 17)], 'logged');
    });

    test('isBefore and isAfter are strict', () {
      final earlier = aDate(2024, 5, 17);
      final later = aDate(2024, 5, 18);
      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier.isBefore(earlier), isFalse);
      expect(earlier.isAfter(earlier), isFalse);
    });

    test('sorts entries that were logged out of order', () {
      final loggedOutOfOrder = [
        aDate(2024, 3, 2),
        aDate(2023, 12, 31),
        aDate(2024, 3, 1),
        aDate(2024, 1, 1),
      ]..sort();

      expect(loggedOutOfOrder, [
        aDate(2023, 12, 31),
        aDate(2024, 1, 1),
        aDate(2024, 3, 1),
        aDate(2024, 3, 2),
      ]);
    });
  });

  group('weekday', () {
    test('matches known days, Monday being 1', () {
      expect(aDate(2024, 5, 13).weekday, 1, reason: 'Monday');
      expect(aDate(2024, 5, 19).weekday, 7, reason: 'Sunday');
      expect(aDate(1970, 1, 1).weekday, 4, reason: 'Thursday, the epoch');
    });

    test('is correct before the epoch', () {
      expect(aDate(1969, 12, 31).weekday, 3, reason: 'Wednesday');
    });

    test('advances one day at a time and wraps', () {
      var date = aDate(2024, 5, 13);
      for (var expected = 1; expected <= 7; expected++) {
        expect(date.weekday, expected);
        date = date.addDays(1);
      }
      expect(date.weekday, 1);
    });
  });

  group('ISO 8601', () {
    test('zero-pads month and day', () {
      expect(aDate(2024, 1, 5).toIso8601(), '2024-01-05');
      expect(aDate(2024, 12, 31).toIso8601(), '2024-12-31');
    });

    test('round-trips', () {
      final dates = [
        aDate(2024, 1, 5),
        aDate(2024, 2, 29),
        aDate(1970, 1, 1),
        aDate(1899, 12, 31),
      ];
      for (final date in dates) {
        expect(CycleDate.parseIso8601(date.toIso8601()), date);
      }
    });

    test('rejects malformed input', () {
      for (final bad in [
        '',
        '2024-1-5',
        '2024/01/05',
        '05-01-2024',
        '2024-01-05T00:00:00Z',
        'today',
      ]) {
        expect(
          () => CycleDate.parseIso8601(bad),
          throwsFormatException,
          reason: 'accepted $bad',
        );
      }
    });

    test('rejects a well-formed string that is not a real date', () {
      expect(() => CycleDate.parseIso8601('2023-02-29'), throwsFormatException);
      expect(() => CycleDate.parseIso8601('2024-13-01'), throwsFormatException);
      expect(() => CycleDate.parseIso8601('2024-00-10'), throwsFormatException);
    });
  });

  test('toString is readable', () {
    expect(aDate(2024, 5, 17).toString(), 'CycleDate(2024-05-17)');
  });
}
