import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/analysis/analysis_page.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// Goldens for the cycles screen.
///
/// Worth reviewing as images rather than only as assertions: section 8 is about
/// how the wording reads in context, and a phrase that is defensible in an ARB
/// file can still land badly sitting under a big number.
///
///     flutter test --update-goldens
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    AnalysisViewData data,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
  }) async {
    await pumpApp(
      tester,
      AnalysisScreen(data: data),
      locale: locale,
      brightness: brightness,
      surface: const Size(420, 900),
    );
    await expectLater(
      find.byType(AnalysisScreen),
      matchesGoldenFile('goldens/analysis_$name.png'),
    );
  }

  testWidgets('nothing logged', (tester) async {
    await expectGolden(tester, analysisFrom([]), 'empty');
  });

  testWidgets('one cycle, too few to summarise', (tester) async {
    await expectGolden(
      tester,
      analysisFrom([aDate(2024, 1, 1), aDate(2024, 1, 29)]),
      'too_few',
    );
  });

  testWidgets('a steady history', (tester) async {
    await expectGolden(
      tester,
      analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 5),
      ),
      'steady',
    );
  });

  testWidgets('a varying history', (tester) async {
    await expectGolden(
      tester,
      analysisFrom([
        aDate(2024, 1, 1),
        aDate(2024, 1, 25), // 24 days
        aDate(2024, 2, 26), // 32 days
        aDate(2024, 3, 21), // 24 days
        aDate(2024, 4, 26), // 36 days
        aDate(2024, 5, 22), // 26 days, then this one is still in progress
      ]),
      'varying',
    );
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(
      tester,
      analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 5),
      ),
      'dark',
      brightness: Brightness.dark,
    );
  });

  testWidgets('German', (tester) async {
    await expectGolden(
      tester,
      analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 29, count: 4),
      ),
      'german',
      locale: const Locale('de'),
    );
  });

  testWidgets('pregnancy, with the figures hidden', (tester) async {
    await expectGolden(
      tester,
      analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 5),
        statisticsVisible: false,
      ),
      'pregnancy',
    );
  });
}
