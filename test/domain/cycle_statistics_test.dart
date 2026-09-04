import 'package:period/domain/logic/cycle_analysis.dart';
import 'package:period/domain/logic/cycle_statistics.dart';
import 'package:period/domain/models/cycle.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  /// Completed cycles of exactly these lengths, back to back.
  List<Cycle> cyclesOf(List<int> lengths) {
    var day = aDate(2024, 1, 1);
    final starts = [day];
    for (final length in lengths) {
      day = day.addDays(length);
      starts.add(day);
    }
    return cyclesFrom(starts).where((c) => !c.isInProgress).toList();
  }

  group('medianCycleLength', () {
    test('is null with nothing to measure', () {
      expect(medianCycleLength(const []), isNull);
      expect(medianCycleLength(cyclesOf(const [])), isNull);
    });

    test('is the value itself for one cycle', () {
      expect(medianCycleLength(cyclesOf([28])), 28);
    });

    test('splits the difference for an even count', () {
      expect(medianCycleLength(cyclesOf([28, 29])), 28.5);
    });

    test('is the middle value for an odd count', () {
      expect(medianCycleLength(cyclesOf([21, 28, 40])), 28);
    });

    test('ignores order', () {
      expect(
        medianCycleLength(cyclesOf([40, 21, 28])),
        medianCycleLength(cyclesOf([21, 28, 40])),
      );
    });

    test('resists a single outlier where a mean would not', () {
      // The reason section 2 specifies median. The mean of these is 33.75.
      expect(medianCycleLength(cyclesOf([28, 28, 29, 50])), 28.5);
    });
  });

  group('cycleLengthSpread', () {
    test('is null with nothing to measure', () {
      expect(cycleLengthSpread(const []), isNull);
    });

    test('is zero for identical cycles', () {
      expect(cycleLengthSpread(cyclesOf([28, 28, 28, 28])), 0);
    });

    test('grows as the user becomes less consistent', () {
      final steady = cycleLengthSpread(cyclesOf([27, 28, 28, 29]))!;
      final varied = cycleLengthSpread(cyclesOf([22, 28, 30, 38]))!;
      expect(varied, greaterThan(steady));
    });

    test('is interquartile, so one outlier moves it only a little', () {
      // A min-to-max measure would double here; the interquartile spread barely
      // shifts, which is what keeps one bad month from widening the window.
      final without = cycleLengthSpread(cyclesOf([27, 28, 28, 29]))!;
      final with_ = cycleLengthSpread(cyclesOf([27, 28, 28, 29, 60]))!;
      expect(with_ - without, lessThan(4));
    });
  });

  group('cycleLengthRange', () {
    test('is null with nothing to measure', () {
      expect(cycleLengthRange(const []), isNull);
    });

    test('is zero for identical cycles', () {
      expect(cycleLengthRange(cyclesOf([28, 28])), 0);
    });

    test('is longest minus shortest', () {
      expect(cycleLengthRange(cyclesOf([24, 28, 36])), 12);
    });

    test('does take the full extremes, unlike the spread', () {
      // The irregularity hint asks whether anything unusual happened at all,
      // which is a different question from how wide a typical cycle is.
      expect(cycleLengthRange(cyclesOf([27, 28, 28, 29, 60])), 33);
    });
  });

  test('in-progress cycles are ignored by every statistic', () {
    final withOpenCycle = cyclesFrom([
      aDate(2024, 1, 1),
      aDate(2024, 1, 29),
      aDate(2024, 2, 26),
    ]);
    expect(withOpenCycle.last.isInProgress, isTrue);
    expect(medianCycleLength(withOpenCycle), 28);
    expect(cycleLengthRange(withOpenCycle), 0);
  });
}
