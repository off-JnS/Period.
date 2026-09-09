import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/logged_summary.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';

import '../support/widgets.dart';

/// Pictures of the history screen.
///
/// The thin states are worth as much attention as the full one: a user with
/// nothing logged is the first person to open this, and an empty screen is the
/// easiest thing in the app to leave looking broken.
void main() {
  final history = AnalysisViewData(
    cycles: [
      for (var i = 0; i < 6; i++)
        CycleSummary(
          startedOn: DateTime(2023, 12 + i, 3),
          lengthInDays: [29, 27, 31, 28, 26, 30][i],
          periodDays: [5, 4, 6, 4, 5, 4][i],
        ),
    ],
    symptoms: const [
      SymptomTally(symptom: Symptom(key: 'cramps'), days: 14),
      SymptomTally(symptom: Symptom(key: 'tiredness'), days: 9),
      SymptomTally(symptom: Symptom(key: 'headache'), days: 5),
      SymptomTally(symptom: Symptom(key: 'bloating'), days: 3),
    ],
    daysLogged: 47,
    typicalLength: 29,
    shortestLength: 26,
    longestLength: 31,
    typicalPeriodDays: 5,
  );

  Future<void> expectGolden(
    WidgetTester tester,
    AnalysisViewData data,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      AnalysisScreen(data: data),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      surface: const Size(400, 1200),
    );
    await expectLater(
      find.byType(AnalysisScreen),
      matchesGoldenFile('goldens/analysis_$name.png'),
    );
  }

  testWidgets('a real history', (tester) async {
    await expectGolden(tester, history, 'history');
  });

  testWidgets('nothing logged yet', (tester) async {
    await expectGolden(tester, const AnalysisViewData(), 'empty');
  });

  testWidgets('one cycle, before there is a typical length', (tester) async {
    await expectGolden(
      tester,
      AnalysisViewData(
        cycles: [
          CycleSummary(
            startedOn: DateTime(2024, 4, 17),
            lengthInDays: 29,
            periodDays: 4,
          ),
        ],
        daysLogged: 4,
        shortestLength: 29,
        longestLength: 29,
        typicalPeriodDays: 4,
      ),
      'one_cycle',
    );
  });

  testWidgets('German', (tester) async {
    await expectGolden(tester, history, 'german', locale: const Locale('de'));
  });

  testWidgets('dark', (tester) async {
    await expectGolden(tester, history, 'dark', brightness: Brightness.dark);
  });

  testWidgets('at twice the text size', (tester) async {
    await expectGolden(tester, history, 'large_text', textScale: 2);
  });
}
