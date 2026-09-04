import 'package:period/domain/logic/cycle_analysis.dart';
import 'package:period/domain/logic/irregularity.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

/// Cycles of the given [lengths], back to back.
List<int> _lengths(List<int> lengths) => lengths;

void main() {
  bool hintFor(List<int> lengths) {
    var day = aDate(2024, 1, 1);
    final starts = [day];
    for (final length in lengths) {
      day = day.addDays(length);
      starts.add(day);
    }
    return shouldSuggestSeeingADoctor(
      eligibleForStatistics(cyclesFrom(starts)),
    );
  }

  group('stays quiet', () {
    test('with no cycles', () {
      expect(shouldSuggestSeeingADoctor(const []), isFalse);
    });

    test('with fewer than three cycles, however varied', () {
      // Not enough to call anything a pattern.
      expect(hintFor(_lengths([24, 38])), isFalse);
    });

    test('for a regular user', () {
      expect(hintFor(_lengths([28, 28, 28, 28])), isFalse);
    });

    test('for ordinary month-to-month variation', () {
      // A hint that fires on this would fire constantly and be dismissed.
      expect(hintFor(_lengths([27, 29, 28, 30])), isFalse);
    });

    test('for a consistently long but stable cycle', () {
      // 35 days every time is unusual but not variable, and it is inside FIGO's
      // normal range. Nothing to raise.
      expect(hintFor(_lengths([35, 35, 35, 35])), isFalse);
    });

    test('for a single unusual month among steady ones', () {
      // One stressful month is not a pattern. Range 28 to 36 is 8, under the
      // threshold, and only one cycle sits outside 24-38.
      expect(hintFor(_lengths([28, 28, 36, 28])), isFalse);
    });
  });

  group('speaks up', () {
    test('when the range is wider than nine days', () {
      expect(hintFor(_lengths([24, 28, 36, 28])), isTrue);
    });

    test('when two or more cycles fall outside the usual range', () {
      // Both 21 and 22 are below FIGO's 24, but the range is only 7 so the
      // first rule does not catch it. This is what the second rule is for.
      expect(hintFor(_lengths([21, 22, 28, 27])), isTrue);
    });

    test('when cycles are consistently long past the usual range', () {
      expect(hintFor(_lengths([40, 41, 40, 41])), isTrue);
    });
  });

  group('boundaries', () {
    test('a range of exactly nine days is not enough', () {
      expect(hintFor(_lengths([28, 28, 37, 28])), isFalse);
    });

    test('a range of ten days is', () {
      expect(hintFor(_lengths([28, 28, 38, 28])), isTrue);
    });

    test('exactly three cycles can trigger it', () {
      expect(hintFor(_lengths([24, 36, 28])), isTrue);
    });

    test('FIGO boundary lengths themselves count as usual', () {
      expect(hintFor(_lengths([24, 24, 24])), isFalse);
      expect(hintFor(_lengths([38, 38, 38])), isFalse);
    });
  });
}
