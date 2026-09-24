import 'package:period/domain/logic/period_length.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  final start = aDate(2024, 5, 1);
  final today = aDate(2024, 5, 20);

  /// Flow on [days] consecutive days from [from], all [flow].
  Map<CycleDate, FlowIntensity> flowRun(
    CycleDate from,
    int days, [
    FlowIntensity flow = FlowIntensity.medium,
  ]) => {for (var i = 0; i < days; i++) from.addDays(i): flow};

  PeriodLength length(
    Map<CycleDate, FlowIntensity> flow, {
    CycleDate? nextStart,
    CycleDate? on,
  }) => periodLength(
    start: start,
    flowByDay: flow,
    today: on ?? today,
    nextStart: nextStart,
  );

  group('periodDuration', () {
    test('counts the run of flow days from the start', () {
      expect(length(flowRun(start, 5)), const KnownPeriodLength(5));
    });

    test('light, medium and heavy all count', () {
      expect(
        length({
          start: FlowIntensity.heavy,
          start.addDays(1): FlowIntensity.medium,
          start.addDays(2): FlowIntensity.light,
        }),
        const KnownPeriodLength(3),
      );
    });

    test('a day recorded as none ends the run', () {
      final flow = flowRun(start, 6)..[start.addDays(3)] = FlowIntensity.none;
      expect(length(flow), const KnownPeriodLength(3));
    });

    test('a day with nothing logged ends the run, even with flow after it', () {
      // A gap is not bridged: the spec counts consecutive days only.
      final flow = {...flowRun(start, 2), ...flowRun(start.addDays(3), 2)};
      expect(length(flow), const KnownPeriodLength(2));
    });

    test('a one-day period is one day', () {
      expect(length(flowRun(start, 1)), const KnownPeriodLength(1));
    });

    test('a long period is counted in full', () {
      expect(length(flowRun(start, 12)), const KnownPeriodLength(12));
    });

    test('no flow on the start day is unknown, not zero', () {
      expect(length({}), const UnknownPeriodLength());
      expect(
        length({start: FlowIntensity.none, ...flowRun(start.addDays(1), 3)}),
        const UnknownPeriodLength(),
      );
    });

    test('stops at the next period start', () {
      expect(
        length(flowRun(start, 10), nextStart: start.addDays(4)),
        const KnownPeriodLength(4),
      );
    });

    test('a run that reaches today is ongoing', () {
      expect(
        length(flowRun(start, 3), on: start.addDays(2)),
        const OngoingPeriodLength(3),
      );
    });

    test('a start today with flow is ongoing at one day', () {
      expect(
        length(flowRun(start, 1), on: start),
        const OngoingPeriodLength(1),
      );
    });

    test('a start today with nothing logged is unknown', () {
      expect(length({}, on: start), const UnknownPeriodLength());
    });

    test('a run that ended yesterday is finished', () {
      expect(
        length(flowRun(start, 3), on: start.addDays(3)),
        const KnownPeriodLength(3),
      );
    });
  });

  group('periodLengths', () {
    test('bounds each period by the next start, whatever the input order', () {
      final starts = [aDate(2024, 5, 1), aDate(2024, 4, 3), aDate(2024, 3, 6)];
      final flow = {
        ...flowRun(aDate(2024, 3, 6), 5),
        ...flowRun(aDate(2024, 4, 3), 30), // logged straight through
        ...flowRun(aDate(2024, 5, 1), 4),
      };
      expect(periodLengths(starts: starts, flowByDay: flow, today: today), [
        const KnownPeriodLength(4),
        // Capped the day before the 1 May start, not 30 days.
        const KnownPeriodLength(28),
        const KnownPeriodLength(5),
      ]);
    });

    test('no starts, no lengths', () {
      expect(periodLengths(starts: [], flowByDay: {}, today: today), isEmpty);
    });
  });

  group('usualPeriodLength', () {
    test('needs at least two finished periods', () {
      expect(usualPeriodLength([]), isNull);
      expect(usualPeriodLength([const KnownPeriodLength(5)]), isNull);
      expect(
        usualPeriodLength([
          const KnownPeriodLength(5),
          const KnownPeriodLength(7),
        ]),
        6,
      );
    });

    test('is the median, so one unusual period barely moves it', () {
      expect(
        usualPeriodLength([
          const KnownPeriodLength(5),
          const KnownPeriodLength(5),
          const KnownPeriodLength(14),
        ]),
        5,
      );
    });

    test('leaves out ongoing and unknown periods', () {
      expect(
        usualPeriodLength([
          const KnownPeriodLength(4),
          const OngoingPeriodLength(2),
          const UnknownPeriodLength(),
        ]),
        isNull,
      );
      expect(
        usualPeriodLength([
          const KnownPeriodLength(4),
          const KnownPeriodLength(6),
          const OngoingPeriodLength(1),
          const UnknownPeriodLength(),
        ]),
        5,
      );
    });
  });
}
