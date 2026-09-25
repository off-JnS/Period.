import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
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

  testWidgets('period lengths from logged flow', (tester) async {
    final starts = regularPeriodStarts(
      from: aDate(2024, 1, 1),
      length: 28,
      count: 5,
    );
    await expectGolden(
      tester,
      analysisFrom(
        starts,
        flowByDay: {
          for (final (start, days) in [
            (starts[0], 5),
            (starts[1], 4),
            (starts[2], 6),
            (starts[3], 5),
            (starts[4], 2),
          ])
            for (var i = 0; i < days; i++)
              start.addDays(i): FlowIntensity.medium,
        },
        today: starts.last.addDays(1),
      ),
      'period_lengths',
    );
  });

  testWidgets('a temperature chart with a positive test', (tester) async {
    final starts = regularPeriodStarts(
      from: aDate(2024, 3, 1),
      length: 28,
      count: 3,
    );
    const readings = [
      3638,
      3642,
      3635,
      3640,
      3637,
      3644,
      3639,
      3641,
      3636,
      3643,
      3640,
      3638,
      3635,
      3662,
      3671,
      3675,
      3680,
      3677,
      3682,
      3679,
      3684,
      3678,
      3681,
      3676,
    ];
    await expectGolden(
      tester,
      analysisFrom(
        starts,
        temperatures: {
          for (var i = 0; i < readings.length; i++)
            if (i != 6) starts[2].addDays(i): readings[i],
        },
        positiveTests: {starts[2].addDays(12)},
        today: starts[2].addDays(readings.length - 1),
      ),
      'temperature',
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
