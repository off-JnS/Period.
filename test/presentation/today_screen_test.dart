import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/logic/pregnancy_week.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

void main() {
  final predicted = PredictedPeriod(
    earliest: aDate(2024, 4, 26),
    latest: aDate(2024, 4, 30),
  );

  group('the estimate', () {
    testWidgets('is shown as a range, never a single date', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(
            cycleDay: 22,
            typicalCycleLength: 28,
            prediction: predicted,
          ),
        ),
      );

      // Section 8: a prediction is a window. The en dash is the range.
      expect(find.textContaining('–'), findsWidgets);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('Cycle day'), findsOneWidget);
    });

    testWidgets('always carries the qualifying wording', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(data: TodayViewData(prediction: predicted, cycleDay: 22)),
      );
      expect(find.text('Estimated, based on your entries'), findsOneWidget);
    });
  });

  group('every not-predicting state says why', () {
    // Showing nothing reads as a bug. Section 10 asks for predictions-off to be
    // a state rather than an absence, and this is what that looks like.
    testWidgets('not enough cycles asks for what it needs', (tester) async {
      await pumpApp(
        tester,
        const TodayScreen(
          data: TodayViewData(prediction: NotEnoughCycles(have: 1, need: 2)),
        ),
      );
      expect(find.textContaining('one more period'), findsOneWidget);
    });

    testWidgets('too variable describes the data, not the person', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const TodayScreen(
          data: TodayViewData(prediction: CyclesTooVariable(9)),
        ),
      );
      expect(find.textContaining('vary too much'), findsOneWidget);
    });

    testWidgets('each disabled mode explains itself', (tester) async {
      const expected = {
        CycleMode.hormonalContraception: 'withdrawal bleed',
        CycleMode.pregnancy: 'still saved',
        CycleMode.perimenopause: 'perimenopause',
      };

      for (final entry in expected.entries) {
        await pumpApp(
          tester,
          TodayScreen(
            data: TodayViewData(prediction: PredictionsDisabled(entry.key)),
          ),
        );
        expect(
          find.textContaining(entry.value),
          findsOneWidget,
          reason: '${entry.key} must explain itself',
        );
      }
    });
  });

  group('the fertile window', () {
    final fertile = FertileWindowEstimate(
      earliest: aDate(2024, 4, 6),
      latest: aDate(2024, 4, 20),
    );

    testWidgets('is absent unless one was estimated', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(data: TodayViewData(prediction: predicted)),
      );
      expect(find.text('Estimated fertile window'), findsNothing);
    });

    testWidgets('always shows the contraception note, never behind a tap', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(prediction: predicted, fertileWindow: fertile),
        ),
      );
      expect(
        find.textContaining('Not suitable for preventing pregnancy'),
        findsOneWidget,
      );
    });
  });

  group('the doctor hint', () {
    testWidgets('is absent by default', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(data: TodayViewData(prediction: predicted)),
      );
      expect(find.textContaining('worth mentioning'), findsNothing);
    });

    testWidgets('is one quiet line, not a card', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(prediction: predicted, showDoctorHint: true),
        ),
      );
      expect(find.text('Cycles varied more than usual'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Cycles varied more than usual'),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
    });

    testWidgets('tapping it gives the full wording, naming nothing', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(prediction: predicted, showDoctorHint: true),
        ),
      );
      await tester.tap(find.text('Cycles varied more than usual'));
      await tester.pumpAndSettle();
      final hint = tester.widget<Text>(find.textContaining('worth mentioning'));
      expect(hint.data, contains('might be worth mentioning to a doctor'));
      // Section 8: never a finding, never a condition.
      expect(hint.data, isNot(contains('abnormal')));
      expect(hint.data, isNot(contains('irregular')));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('worth mentioning'), findsNothing);
    });

    testWidgets('can be dismissed', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(prediction: predicted, showDoctorHint: true),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Cycles varied more than usual'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('the ring speaks its value', (tester) async {
      // An arc conveys nothing to a screen reader.
      await pumpApp(
        tester,
        const TodayScreen(
          data: TodayViewData(
            cycleDay: 22,
            typicalCycleLength: 28,
            prediction: NotEnoughCycles(have: 0, need: 2),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Cycle day 22'), findsOneWidget);
    });

    testWidgets('survives 200% text without overflowing', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(
            cycleDay: 22,
            typicalCycleLength: 28,
            prediction: predicted,
            fertileWindow: FertileWindowEstimate(
              earliest: aDate(2024, 4, 6),
              latest: aDate(2024, 4, 20),
            ),
            showDoctorHint: true,
          ),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives German, which runs longer than English', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: const TodayViewData(
            prediction: PredictionsDisabled(CycleMode.perimenopause),
          ),
        ),
        locale: const Locale('de'),
      );
      expect(tester.takeException(), isNull);
      // The large title and its collapsed twin are both in the tree.
      expect(find.text('Heute'), findsWidgets);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(data: TodayViewData(prediction: predicted, cycleDay: 22)),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('what was logged today', () {
    testWidgets('lists each kind on its own line', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(
            prediction: const NotEnoughCycles(have: 0, need: 2),
            todayEntry: aDayEntry(
              date: aDate(2024, 5, 17),
              symptoms: {
                aSymptom(key: 'cramps'),
                aSymptom(key: 'mood.sad'),
                aSymptom(key: 'mood.calm'),
                aSymptom(key: 'discharge.creamy'),
                aSymptom(key: 'sex.protected'),
                aSymptom(key: 'pill.taken'),
              },
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Pill taken'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cramps'), findsOneWidget);
      // In the order offered, not alphabetical.
      expect(find.text('Mood: Calm, Sad'), findsOneWidget);
      expect(find.text('Discharge: Creamy'), findsOneWidget);
      expect(find.text('Sex: Protected'), findsOneWidget);
      expect(find.text('Pill taken'), findsOneWidget);
    });

    testWidgets('lists the temperature and ovulation test', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(
            prediction: const NotEnoughCycles(have: 0, need: 2),
            todayEntry: aDayEntry(
              date: aDate(2024, 5, 17),
              symptoms: {aSymptom(key: 'ovulationTest.positive')},
            ).copyWith(temperatureCentiCelsius: 3668),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Ovulation test: Positive'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Temperature: 36.68 °C'), findsOneWidget);
      expect(find.text('Ovulation test: Positive'), findsOneWidget);
    });
  });

  group('in pregnancy mode', () {
    Future<void> pumpWith(WidgetTester tester, PregnancyCount count) => pumpApp(
      tester,
      TodayScreen(
        data: TodayViewData(
          cycleDay: 88,
          prediction: const PredictionsDisabled(CycleMode.pregnancy),
          pregnancy: count,
        ),
      ),
    );

    testWidgets('shows weeks plus days in place of the cycle day', (
      tester,
    ) async {
      await pumpWith(
        tester,
        const PregnancyCounting(PregnancyWeek(weeks: 12, days: 3)),
      );
      expect(find.text('12+3'), findsOneWidget);
      expect(find.text('weeks + days'), findsOneWidget);
      expect(find.text('88'), findsNothing);
      expect(
        find.bySemanticsLabel('Pregnancy: 12 weeks and 3 days'),
        findsOneWidget,
      );
      expect(find.textContaining('first day of your last period'), findsOne);
    });

    testWidgets('never shows a due date', (tester) async {
      await pumpWith(
        tester,
        const PregnancyCounting(PregnancyWeek(weeks: 38, days: 0)),
      );
      expect(find.textContaining('due'), findsNothing);
      expect(find.textContaining('Due'), findsNothing);
    });

    testWidgets('asks for the last period when there is none', (tester) async {
      await pumpWith(tester, const PregnancyNeedsLastPeriod());
      expect(
        find.textContaining('Log the first day of your last period'),
        findsOne,
      );
    });

    testWidgets('after 44 weeks asks, without assuming, about the mode', (
      tester,
    ) async {
      await pumpWith(tester, const PregnancyCounterEnded());
      expect(find.textContaining('still right for you'), findsOneWidget);
      // Back to the plain cycle day, not a week count.
      expect(find.text('88'), findsOneWidget);
    });
  });

  group('the date and countdown', () {
    Future<void> pumpOn(WidgetTester tester, PeriodPrediction prediction) =>
        pumpApp(
          tester,
          TodayScreen(
            data: TodayViewData(
              today: aDate(2024, 4, 14),
              countdown: countdownTo(prediction, aDate(2024, 4, 14)),
              prediction: prediction,
            ),
          ),
        );

    testWidgets('shows the date and the window counted in days', (
      tester,
    ) async {
      await pumpOn(tester, predicted);
      expect(find.text('Sunday, April 14'), findsOneWidget);
      expect(find.text('in 12–16 days'), findsOneWidget);
      expect(find.bySemanticsLabel('Next period: in 12–16 days'), findsOne);
    });

    testWidgets('inside the window says it could start any day', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(
            today: aDate(2024, 4, 27),
            countdown: countdownTo(predicted, aDate(2024, 4, 27)),
            prediction: predicted,
          ),
        ),
      );
      expect(find.text('could start any day'), findsOneWidget);
    });

    testWidgets('has no countdown without a window', (tester) async {
      await pumpOn(tester, const NotEnoughCycles(have: 1, need: 2));
      expect(find.text('Sunday, April 14'), findsOneWidget);
      expect(find.textContaining('days'), findsNothing);
    });

    testWidgets('appears at once with reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: appHarness(
            TodayScreen(
              data: TodayViewData(
                today: aDate(2024, 4, 14),
                countdown: countdownTo(predicted, aDate(2024, 4, 14)),
                prediction: predicted,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // No frames to wait for: nothing is still fading in.
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('in 12–16 days'), findsOneWidget);
    });
  });
}
