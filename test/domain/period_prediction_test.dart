import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  group('when there is not enough to go on', () {
    test('no cycles at all', () {
      final result = predictNextPeriod(periodStarts: const []);
      expect(result, isA<NotEnoughCycles>());
      expect((result as NotEnoughCycles).have, 0);
    });

    test('one period start is not one cycle', () {
      final result = predictNextPeriod(periodStarts: [aDate(2024, 1, 1)]);
      expect(result, isA<NotEnoughCycles>());
    });

    test('two starts give only one completed cycle, still not enough', () {
      final result = predictNextPeriod(
        periodStarts: [aDate(2024, 1, 1), aDate(2024, 1, 29)],
      );
      expect(result, isA<NotEnoughCycles>());
      expect((result as NotEnoughCycles).have, 1);
      expect(result.need, cyclesNeededToPredict);
    });

    test('never falls back to 28 days', () {
      // The industry's error. Only ~13% of cycles are 28 days, so guessing it is
      // worse than admitting there is nothing to say.
      final result = predictNextPeriod(periodStarts: [aDate(2024, 1, 1)]);
      expect(result, isNot(isA<PredictedPeriod>()));
    });
  });

  group('a regular user', () {
    test('gets a window centred on her own median', () {
      final result = predictNextPeriod(
        periodStarts: regularPeriodStarts(
          from: aDate(2024, 1, 1),
          length: 28,
          count: 4,
        ),
      );
      // Last start 2024-03-25; median 28 -> centre 2024-04-22.
      expect(result, isA<PredictedPeriod>());
      final window = result as PredictedPeriod;
      expect(window.contains(aDate(2024, 4, 22)), isTrue);
    });

    test('still gets a range, never a single day', () {
      // Section 8 forbids stating a prediction as certainty, however regular
      // the user is.
      final result = predictNextPeriod(
        periodStarts: regularPeriodStarts(
          from: aDate(2024, 1, 1),
          length: 28,
          count: 6,
        ),
      );
      final window = result as PredictedPeriod;
      expect(window.spanInDays, greaterThanOrEqualTo(3));
      expect(window.earliest, isNot(window.latest));
    });

    test('a 21-day cycle is predicted on its own terms', () {
      final result = predictNextPeriod(
        periodStarts: regularPeriodStarts(
          from: aDate(2024, 1, 1),
          length: 21,
          count: 4,
        ),
      );
      final window = result as PredictedPeriod;
      expect(
        window.contains(aDate(2024, 3, 25)),
        isTrue,
        reason: 'starts 1, 22 Jan, 12 Feb, 4 Mar; 4 Mar plus 21 days',
      );
    });

    test('a 40-day cycle is predicted on its own terms', () {
      final result = predictNextPeriod(
        periodStarts: regularPeriodStarts(
          from: aDate(2024, 1, 1),
          length: 40,
          count: 4,
        ),
      );
      final window = result as PredictedPeriod;
      expect(
        window.contains(aDate(2024, 6, 9)),
        isTrue,
        reason: 'starts 1 Jan, 10 Feb, 21 Mar, 30 Apr; 30 Apr plus 40 days',
      );
    });
  });

  group('an irregular user', () {
    test('gets a wider window than a regular one', () {
      final regular = predictNextPeriod(
        periodStarts: regularPeriodStarts(
          from: aDate(2024, 1, 1),
          length: 28,
          count: 5,
        ),
      ) as PredictedPeriod;

      // Lengths 26, 28, 29, 31 -- varied, but not so varied that the window
      // stops being worth drawing.
      final irregular = predictNextPeriod(
        periodStarts: [
          aDate(2024, 1, 1),
          aDate(2024, 1, 27),
          aDate(2024, 2, 24),
          aDate(2024, 3, 24),
          aDate(2024, 4, 24),
        ],
      ) as PredictedPeriod;

      expect(irregular.spanInDays, greaterThan(regular.spanInDays));
    });

    test(
      'is told the cycles are too variable rather than shown a wide band',
      () {
        // Wildly varying but individually plausible lengths.
        final result = predictNextPeriod(
          periodStarts: [
            aDate(2024, 1, 1),
            aDate(2024, 1, 15), // 14
            aDate(2024, 3, 1), // 46
            aDate(2024, 3, 16), // 15
            aDate(2024, 4, 30), // 45
            aDate(2024, 5, 15), // 15
          ],
        );
        expect(result, isA<CyclesTooVariable>());
        expect(
          (result as CyclesTooVariable).halfWidthDays,
          greaterThan(widestUsefulHalfWidth),
        );
      },
    );
  });

  group('corrections and gaps', () {
    test('a retroactively corrected start changes the prediction', () {
      final before = predictNextPeriod(
        periodStarts: [
          aDate(2024, 1, 1),
          aDate(2024, 1, 29),
          aDate(2024, 2, 26),
        ],
      ) as PredictedPeriod;

      final after = predictNextPeriod(
        periodStarts: [
          aDate(2024, 1, 1),
          aDate(2024, 1, 29),
          aDate(2024, 2, 24),
        ],
      ) as PredictedPeriod;

      expect(
        after.earliest,
        isNot(before.earliest),
        reason:
            'nothing derived is stored, so a correction takes effect at once',
      );
    });

    test('predicts from the newest start, not the newest completed cycle', () {
      // Otherwise an in-progress cycle would be ignored and the prediction
      // would be a month stale.
      final starts = regularPeriodStarts(
        from: aDate(2024, 1, 1),
        length: 28,
        count: 4,
      );
      final result = predictNextPeriod(periodStarts: starts) as PredictedPeriod;
      expect(result.earliest.isAfter(starts.last), isTrue);
    });

    test('a three-month gap widens rather than breaks the prediction', () {
      final result = predictNextPeriod(
        periodStarts: [
          aDate(2024, 1, 1),
          aDate(2024, 1, 29),
          aDate(2024, 4, 20),
          aDate(2024, 5, 18),
        ],
      );
      expect(result, anyOf(isA<PredictedPeriod>(), isA<CyclesTooVariable>()));
    });

    test('an artifact cycle does not poison the median', () {
      final withArtifact = predictNextPeriod(
        periodStarts: [
          ...regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 4),
          aDate(2024, 3, 27), // a double-logged start two days later
        ],
      );
      expect(withArtifact, isA<PredictedPeriod>());
    });
  });

  group('cycle modes', () {
    final regular = regularPeriodStarts(
      from: aDate(2024, 1, 1),
      length: 28,
      count: 4,
    );

    test('natural predicts', () {
      expect(predictNextPeriod(periodStarts: regular), isA<PredictedPeriod>());
    });

    test('hormonal contraception does not, and says why', () {
      final result = predictNextPeriod(
        periodStarts: regular,
        settings: const CycleSettings(mode: CycleMode.hormonalContraception),
      );
      expect(result, isA<PredictionsDisabled>());
      expect(
        (result as PredictionsDisabled).mode,
        CycleMode.hormonalContraception,
      );
    });

    test('pregnancy does not', () {
      expect(
        predictNextPeriod(
          periodStarts: regular,
          settings: const CycleSettings(mode: CycleMode.pregnancy),
        ),
        isA<PredictionsDisabled>(),
      );
    });

    test('perimenopause is off by default', () {
      expect(
        predictNextPeriod(
          periodStarts: regular,
          settings: const CycleSettings(mode: CycleMode.perimenopause),
        ),
        isA<PredictionsDisabled>(),
      );
    });

    test('perimenopause predicts once opted in', () {
      expect(
        predictNextPeriod(
          periodStarts: regular,
          settings: const CycleSettings(
            mode: CycleMode.perimenopause,
            predictionsOptedIn: true,
          ),
        ),
        isA<PredictedPeriod>(),
      );
    });

    test('opting in cannot re-enable contraception or pregnancy', () {
      // There is no natural cycle to predict from, so opting in would not make a
      // prediction meaningful -- only confident.
      for (final mode in [
        CycleMode.hormonalContraception,
        CycleMode.pregnancy,
      ]) {
        expect(
          predictNextPeriod(
            periodStarts: regular,
            settings: CycleSettings(mode: mode, predictionsOptedIn: true),
          ),
          isA<PredictionsDisabled>(),
          reason: '$mode must stay off',
        );
      }
    });

    test('the disabled check comes before the not-enough-data check', () {
      // A user on the pill with no history should be told predictions are off,
      // not asked to log more cycles that would never be used.
      expect(
        predictNextPeriod(
          periodStarts: const [],
          settings: const CycleSettings(mode: CycleMode.pregnancy),
        ),
        isA<PredictionsDisabled>(),
      );
    });
  });
}
