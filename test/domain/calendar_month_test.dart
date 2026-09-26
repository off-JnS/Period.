import 'package:period/domain/logic/calendar_month.dart';
import 'package:period/domain/logic/period_length.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  final today = aDate(2024, 9, 20);

  Map<CycleDate, FlowIntensity> flow(Iterable<CycleDate> days) => {
    for (final day in days) day: FlowIntensity.medium,
  };

  List<CycleDate> run(CycleDate from, int days) => [
    for (var i = 0; i < days; i++) from.addDays(i),
  ];

  group('periodsStartingIn', () {
    test('no starts, no periods', () {
      expect(
        periodsStartingIn(
          year: 2024,
          month: 9,
          starts: const [],
          flowByDay: const {},
          today: today,
        ),
        isEmpty,
      );
    });

    test('a finished period with its length and last day', () {
      final start = aDate(2024, 9, 3);
      final periods = periodsStartingIn(
        year: 2024,
        month: 9,
        starts: [start],
        flowByDay: flow(run(start, 5)),
        today: today,
      );
      expect(periods, [
        MonthPeriod(start: start, length: const KnownPeriodLength(5)),
      ]);
      expect(periods.single.lastDay, aDate(2024, 9, 7));
    });

    test(
      'a period crossing into the next month belongs to its start month',
      () {
        final start = aDate(2024, 8, 30);
        final flowByDay = flow(run(start, 5));
        final starts = [start];

        final august = periodsStartingIn(
          year: 2024,
          month: 8,
          starts: starts,
          flowByDay: flowByDay,
          today: today,
        );
        expect(august.single.lastDay, aDate(2024, 9, 3));
        expect(
          periodsStartingIn(
            year: 2024,
            month: 9,
            starts: starts,
            flowByDay: flowByDay,
            today: today,
          ),
          isEmpty,
        );
      },
    );

    test('an ongoing period has no last day yet', () {
      final start = aDate(2024, 9, 18);
      final period = periodsStartingIn(
        year: 2024,
        month: 9,
        starts: [start],
        flowByDay: flow(run(start, 3)),
        today: today,
      ).single;
      expect(period.length, const OngoingPeriodLength(3));
      expect(period.lastDay, isNull);
    });

    test('a start with no flow logged has an unknown length', () {
      final period = periodsStartingIn(
        year: 2024,
        month: 9,
        starts: [aDate(2024, 9, 1)],
        flowByDay: const {},
        today: today,
      ).single;
      expect(period.length, const UnknownPeriodLength());
      expect(period.lastDay, isNull);
    });

    test('two periods in one month, given out of order, come oldest first and '
        'the first is cut off by the second', () {
      final first = aDate(2024, 9, 1);
      final second = aDate(2024, 9, 4);
      final periods = periodsStartingIn(
        year: 2024,
        month: 9,
        starts: [second, first],
        flowByDay: flow(run(first, 10)),
        today: today,
      );
      expect(periods.map((p) => p.start), [first, second]);
      expect(periods.first.length, const KnownPeriodLength(3));
    });

    test('a retroactively corrected start reads from the corrected day', () {
      final corrected = aDate(2024, 9, 5);
      final period = periodsStartingIn(
        year: 2024,
        month: 9,
        starts: [corrected],
        flowByDay: flow(run(aDate(2024, 9, 4), 5)),
        today: today,
      ).single;
      expect(period.length, const KnownPeriodLength(4));
    });
  });

  group('isPeriodDay', () {
    final start = aDate(2024, 9, 3);

    test('a start is a period day even with no flow logged', () {
      expect(isPeriodDay(start, starts: {start}, flowByDay: const {}), isTrue);
    });

    test('light, medium and heavy flow are period days; none is not', () {
      for (final intensity in FlowIntensity.values) {
        expect(
          isPeriodDay(
            aDate(2024, 9, 10),
            starts: const {},
            flowByDay: {aDate(2024, 9, 10): intensity},
          ),
          intensity != FlowIntensity.none,
          reason: intensity.name,
        );
      }
    });

    test('a day with nothing logged is not', () {
      expect(
        isPeriodDay(aDate(2024, 9, 10), starts: {start}, flowByDay: const {}),
        isFalse,
      );
    });
  });

  group('rangeTouchesMonth', () {
    bool touches(CycleDate from, CycleDate to) =>
        rangeTouchesMonth(earliest: from, latest: to, year: 2024, month: 9);

    test('inside, straddling either end, and outside', () {
      expect(touches(aDate(2024, 9, 10), aDate(2024, 9, 14)), isTrue);
      expect(touches(aDate(2024, 8, 29), aDate(2024, 9, 1)), isTrue);
      expect(touches(aDate(2024, 9, 30), aDate(2024, 10, 4)), isTrue);
      expect(touches(aDate(2024, 8, 1), aDate(2024, 8, 31)), isFalse);
      expect(touches(aDate(2024, 10, 1), aDate(2024, 10, 5)), isFalse);
    });

    test('a range covering the whole month touches it', () {
      expect(touches(aDate(2024, 8, 20), aDate(2024, 10, 10)), isTrue);
    });
  });
}
