import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/logged_summary.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';

import '../support/widgets.dart';

/// The analysis screen as a pure widget.
///
/// Two claims carry this screen. It must never read as a prediction -- it is
/// the one screen in the app that only reports. And every number drawn as a bar
/// must also be readable as text, because section 9 forbids information carried
/// by shape alone and a chart is where that is easiest to forget.
void main() {
  AnalysisViewData history({int cycles = 4}) => AnalysisViewData(
    cycles: [
      for (var i = 0; i < cycles; i++)
        CycleSummary(
          startedOn: DateTime(2024, 1 + i, 3),
          lengthInDays: 27 + i,
          periodDays: 4 + (i % 2),
        ),
    ],
    symptoms: const [
      SymptomTally(symptom: Symptom(key: 'cramps'), days: 9),
      SymptomTally(symptom: Symptom(key: 'headache'), days: 4),
    ],
    daysLogged: 31,
    typicalLength: 28,
    shortestLength: 27,
    longestLength: 30,
    typicalPeriodDays: 5,
  );

  Future<void> pumpAnalysis(
    WidgetTester tester, {
    AnalysisViewData? data,
    Locale locale = const Locale('en'),
  }) async {
    await pumpApp(
      tester,
      AnalysisScreen(data: data ?? history()),
      locale: locale,
      surface: const Size(400, 1400),
    );
  }

  group('it reports, it does not predict', () {
    testWidgets('no word on it suggests a forecast', (tester) async {
      // The one screen that must never imply what happens next. Section 8
      // forbids stating a prediction as certainty; this screen contains no
      // prediction to state.
      await pumpAnalysis(tester);

      for (final word in [
        'next',
        'expect',
        'due',
        'predict',
        'estimat',
        'forecast',
        'will be',
      ]) {
        expect(
          find.textContaining(RegExp(word, caseSensitive: false)),
          findsNothing,
          reason: 'the history screen must not say "$word"',
        );
      }
    });

    testWidgets('nothing on it diagnoses or names a condition', (tester) async {
      await pumpAnalysis(tester);

      for (final word in [
        'normal',
        'abnormal',
        'irregular',
        'disorder',
        'diagnos',
        'healthy',
        'concern',
      ]) {
        expect(
          find.textContaining(RegExp(word, caseSensitive: false)),
          findsNothing,
          reason: 'the history screen must not say "$word"',
        );
      }
    });
  });

  group('every value is readable as text, not only as a bar', () {
    testWidgets('the typical length', (tester) async {
      await pumpAnalysis(tester);
      expect(find.text('28 days'), findsWidgets);
    });

    testWidgets('the range', (tester) async {
      await pumpAnalysis(tester);
      expect(find.textContaining('27'), findsWidgets);
      expect(find.textContaining('30'), findsWidgets);
    });

    testWidgets('every cycle in the chart appears in the list', (tester) async {
      // The chart's numbers live here. A bar whose height is the only place a
      // value exists is exactly what section 9 rules out.
      await pumpAnalysis(tester, data: history(cycles: 3));

      for (final length in ['27 days', '28 days', '29 days']) {
        expect(find.text(length), findsWidgets, reason: 'missing $length');
      }
    });

    testWidgets('symptom counts, beside their bars', (tester) async {
      await pumpAnalysis(tester);
      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('9 days'), findsWidgets);
      expect(find.text('Headache'), findsOneWidget);
    });

    testWidgets('the chart is described for a screen reader', (tester) async {
      // A chart says nothing on its own; this points at the list that carries
      // every value rather than leaving an unexplained blank.
      await pumpAnalysis(tester, data: history(cycles: 3));
      expect(
        find.bySemanticsLabel(RegExp('chart of 3 cycle lengths')),
        findsOneWidget,
      );
    });
  });

  group('the thin states, which are what a new user sees', () {
    testWidgets('nothing logged says so rather than showing a blank', (
      tester,
    ) async {
      await pumpAnalysis(tester, data: const AnalysisViewData());

      expect(find.text('Nothing logged yet'), findsOneWidget);
      expect(find.textContaining('will show up here'), findsOneWidget);
    });

    testWidgets('one cycle says what is missing instead of guessing', (
      tester,
    ) async {
      await pumpAnalysis(
        tester,
        data: AnalysisViewData(
          cycles: [
            CycleSummary(
              startedOn: DateTime(2024, 3, 3),
              lengthInDays: 29,
              periodDays: 4,
            ),
          ],
          daysLogged: 4,
        ),
      );

      expect(find.textContaining('Two complete cycles'), findsOneWidget);
      expect(find.text('29 days'), findsWidgets);
    });

    testWidgets('one cycle draws no chart', (tester) async {
      // A single bar is not a comparison, and a chart of one is a decoration.
      await pumpAnalysis(tester, data: history(cycles: 1));
      expect(find.byType(AnalysisScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('chart of')), findsNothing);
    });

    testWidgets('a start with no flow logged shows no bleeding count', (
      tester,
    ) async {
      await pumpAnalysis(
        tester,
        data: AnalysisViewData(
          cycles: [
            CycleSummary(
              startedOn: DateTime(2024, 3, 3),
              lengthInDays: 29,
              periodDays: 0,
            ),
          ],
          daysLogged: 1,
        ),
      );

      expect(find.textContaining('bleeding'), findsNothing);
    });
  });

  testWidgets('German', (tester) async {
    await pumpAnalysis(tester, locale: const Locale('de'));
    expect(find.text('Dein Verlauf'), findsOneWidget);
    expect(find.text('28 Tage'), findsWidgets);
  });
}
