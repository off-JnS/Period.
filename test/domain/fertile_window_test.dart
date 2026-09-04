import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  final regular = regularPeriodStarts(
    from: aDate(2024, 1, 1),
    length: 28,
    count: 5,
  );
  final prediction = predictNextPeriod(periodStarts: regular);

  group('opting in', () {
    test('nothing is estimated unless the user asked for it', () {
      // Off by default: the app's most misusable feature, and the one where the
      // evidence for calendar methods is weakest.
      expect(
        estimateFertileWindow(prediction: prediction, optedIn: false),
        isNull,
      );
    });

    test('an estimate appears once opted in', () {
      expect(
        estimateFertileWindow(prediction: prediction, optedIn: true),
        isNotNull,
      );
    });
  });

  group('when there is nothing to count back from', () {
    test('no prediction means no fertile window', () {
      for (final none in [
        predictNextPeriod(periodStarts: [aDate(2024, 1, 1)]),
        predictNextPeriod(periodStarts: const []),
      ]) {
        expect(estimateFertileWindow(prediction: none, optedIn: true), isNull);
      }
    });

    test('predictions disabled means no fertile window', () {
      // Opting into the fertile window must not smuggle prediction back in for
      // a user who turned it off.
      final disabled = predictNextPeriod(
        periodStarts: regular,
        settings: const CycleSettings(mode: CycleMode.pregnancy),
      );
      expect(
        estimateFertileWindow(prediction: disabled, optedIn: true),
        isNull,
      );
    });

    test('too-variable cycles mean no fertile window', () {
      final tooVariable = predictNextPeriod(
        periodStarts: [
          aDate(2024, 1, 1),
          aDate(2024, 1, 15),
          aDate(2024, 3, 1),
          aDate(2024, 3, 16),
          aDate(2024, 4, 30),
          aDate(2024, 5, 15),
        ],
      );
      expect(tooVariable, isA<CyclesTooVariable>());
      expect(
        estimateFertileWindow(prediction: tooVariable, optedIn: true),
        isNull,
      );
    });
  });

  group('the arithmetic', () {
    final window = prediction as PredictedPeriod;
    final fertile = estimateFertileWindow(
      prediction: prediction,
      optedIn: true,
    )!;

    test('ends before the earliest predicted period day', () {
      // Ovulation precedes the period by at least the shortest luteal phase, so
      // the fertile window must close before the period could begin.
      expect(fertile.latest.isBefore(window.earliest), isTrue);
    });

    test(
      'is counted back from the period, not forward from the last start',
      () {
        // The point of the whole method. Follicular phase 95% CI is 10-30 days,
        // luteal 7-17, so counting forward runs through the wider spread.
        expect(fertile.latest, window.latest.subtractDays(shortestLutealPhase));
        expect(
          fertile.earliest,
          window.earliest
              .subtractDays(longestLutealPhase)
              .subtractDays(fertileDaysBeforeOvulation),
        );
      },
    );

    test('inherits the prediction window uncertainty', () {
      // An estimate built on an estimate carries both. A wider prediction must
      // produce a wider fertile window, never the same one.
      final vaguer = predictNextPeriod(
        periodStarts: [
          aDate(2024, 1, 1),
          aDate(2024, 1, 27),
          aDate(2024, 2, 24),
          aDate(2024, 3, 24),
          aDate(2024, 4, 24),
        ],
      );
      final vaguerFertile = estimateFertileWindow(
        prediction: vaguer,
        optedIn: true,
      )!;

      expect(
        vaguerFertile.spanInDays,
        greaterThan(fertile.spanInDays),
        reason: 'a less certain period means a less certain fertile window',
      );
    });

    test('is wide, and that is the honest answer', () {
      // Wilcox et al. found at least a 10% chance of being in the fertile window
      // on every day from 6 to 21 of the cycle. A narrow window here would be a
      // more precise lie, not a better estimate.
      expect(fertile.spanInDays, greaterThanOrEqualTo(6));
    });

    test('contains its own boundaries', () {
      expect(fertile.contains(fertile.earliest), isTrue);
      expect(fertile.contains(fertile.latest), isTrue);
      expect(fertile.contains(fertile.earliest.subtractDays(1)), isFalse);
      expect(fertile.contains(fertile.latest.addDays(1)), isFalse);
    });
  });
}
