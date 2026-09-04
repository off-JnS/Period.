import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/dates.dart';
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
      expect(find.text('Day 22'), findsOneWidget);
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

    testWidgets('suggests a conversation without naming anything', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(prediction: predicted, showDoctorHint: true),
        ),
      );
      final hint = tester.widget<Text>(find.textContaining('worth mentioning'));
      expect(hint.data, contains('might be worth mentioning to a doctor'));
      // Section 8: never a finding, never a condition.
      expect(hint.data, isNot(contains('abnormal')));
      expect(hint.data, isNot(contains('irregular')));
    });

    testWidgets('can be dismissed', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: TodayViewData(prediction: predicted, showDoctorHint: true),
        ),
      );
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('worth mentioning'), findsNothing);
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
      expect(find.text('Heute'), findsOneWidget);
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
}
