import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/models.dart';
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
          data: aTodayView(
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
        TodayScreen(data: aTodayView(prediction: predicted, cycleDay: 22)),
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
        TodayScreen(
          data: aTodayView(prediction: NotEnoughCycles(have: 1, need: 2)),
        ),
      );
      expect(find.textContaining('one more period'), findsOneWidget);
    });

    testWidgets('too variable describes the data, not the person', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(data: aTodayView(prediction: CyclesTooVariable(9))),
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
            data: aTodayView(prediction: PredictionsDisabled(entry.key)),
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
        TodayScreen(data: aTodayView(prediction: predicted)),
      );
      expect(find.text('Estimated fertile window'), findsNothing);
    });

    testWidgets('always shows the contraception note, never behind a tap', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: aTodayView(prediction: predicted, fertileWindow: fertile),
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
        TodayScreen(data: aTodayView(prediction: predicted)),
      );
      expect(find.textContaining('worth mentioning'), findsNothing);
    });

    testWidgets('suggests a conversation without naming anything', (
      tester,
    ) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: aTodayView(prediction: predicted, showDoctorHint: true),
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
          data: aTodayView(prediction: predicted, showDoctorHint: true),
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
        TodayScreen(
          data: aTodayView(
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
          data: aTodayView(
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
          data: aTodayView(
            prediction: PredictionsDisabled(CycleMode.perimenopause),
          ),
        ),
        locale: const Locale('de'),
      );
      expect(tester.takeException(), isNull);
      // Was find.text('Heute') -- the app bar's old title, used as a stand-in
      // for "German rendered". The bar carries the date now, so this asserts
      // the same thing against something German that is still on the screen:
      // a weekday and a month name no English build would produce.
      expect(find.text('Freitag, 17. Mai'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(data: aTodayView(prediction: predicted, cycleDay: 22)),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('running late', () {
    // Section 9: no information by colour alone. The ring draws the overrun in
    // a second colour, so being late has to be said in words as well -- and
    // this is the state a user is most likely to have opened the app for.
    testWidgets('is said in words, not only drawn', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: aTodayView(
            cycleDay: 34,
            typicalCycleLength: 28,
            prediction: predicted,
          ),
        ),
      );
      expect(find.text('6 days later than your usual 28'), findsOneWidget);
    });

    testWidgets('one day late reads as a day, not 1 days', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: aTodayView(
            cycleDay: 29,
            typicalCycleLength: 28,
            prediction: predicted,
          ),
        ),
      );
      expect(find.text('1 day later than your usual 28'), findsOneWidget);
    });

    testWidgets('says nothing on the usual length itself', (tester) async {
      await pumpApp(
        tester,
        TodayScreen(
          data: aTodayView(
            cycleDay: 28,
            typicalCycleLength: 28,
            prediction: predicted,
          ),
        ),
      );
      expect(find.textContaining('later than'), findsNothing);
    });

    testWidgets('says nothing without a length to compare against', (
      tester,
    ) async {
      // A user with one cycle has no typical length. Comparing against 28 would
      // be the industry's mistake, and saying she is late would be inventing it.
      await pumpApp(
        tester,
        TodayScreen(data: aTodayView(cycleDay: 40, prediction: predicted)),
      );
      expect(find.textContaining('later than'), findsNothing);
    });

    testWidgets('is phrased as an observation, never a warning', (
      tester,
    ) async {
      // Section 8: never a finding, never a claim about her health.
      await pumpApp(
        tester,
        TodayScreen(
          data: aTodayView(
            cycleDay: 34,
            typicalCycleLength: 28,
            prediction: predicted,
          ),
        ),
      );
      final text = tester
          .widget<Text>(find.textContaining('later than'))
          .data!
          .toLowerCase();
      for (final alarming in [
        'late!',
        'overdue',
        'warning',
        'abnormal',
        'missed',
      ]) {
        expect(text, isNot(contains(alarming)), reason: 'found "$alarming"');
      }
    });
  });
}
