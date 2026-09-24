import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// Golden tests for the calendar, as CLAUDE.md section 7 requires.
///
/// These carry more weight here than on the Today screen. Section 9's rule that
/// no state is told by colour alone is a claim about what the grid *looks* like,
/// and a person reviewing these images is the only thing that can confirm the
/// disc, the rings and the dot really are distinguishable from one another.
///
/// Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
void main() {
  final today = aDate(2024, 5, 17);

  Future<void> expectGolden(
    WidgetTester tester,
    CalendarViewData data,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      CalendarScreen(data: data),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      surface: const Size(420, 820),
    );
    await expectLater(
      find.byType(CalendarScreen),
      matchesGoldenFile('goldens/calendar_$name.png'),
    );
  }

  testWidgets('an empty month', (tester) async {
    await expectGolden(
      tester,
      CalendarViewData(year: 2024, month: 5, today: today),
      'empty',
    );
  });

  testWidgets('every marker at once', (tester) async {
    // The review surface for section 9: a filled disc, a solid ring, a dashed
    // ring and a dot all on screen together, so they can be compared.
    await expectGolden(
      tester,
      CalendarViewData(
        year: 2024,
        month: 5,
        today: today,
        periodStarts: {aDate(2024, 5, 3)},
        loggedDays: {
          aDate(2024, 5, 3),
          aDate(2024, 5, 4),
          aDate(2024, 5, 5),
          aDate(2024, 5, 9),
        },
        predicted: PredictedPeriod(
          earliest: aDate(2024, 5, 29),
          latest: aDate(2024, 6, 2),
        ),
      ),
      'markers',
    );
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(
      tester,
      CalendarViewData(
        year: 2024,
        month: 5,
        today: today,
        periodStarts: {aDate(2024, 5, 3)},
        loggedDays: {aDate(2024, 5, 3), aDate(2024, 5, 4)},
        predicted: PredictedPeriod(
          earliest: aDate(2024, 5, 29),
          latest: aDate(2024, 6, 2),
        ),
      ),
      'dark',
      brightness: Brightness.dark,
    );
  });

  testWidgets('German, which starts the week on Monday', (tester) async {
    await expectGolden(
      tester,
      CalendarViewData(
        year: 2024,
        month: 5,
        today: today,
        periodStarts: {aDate(2024, 5, 3)},
      ),
      'german',
      locale: const Locale('de'),
    );
  });

  testWidgets('a six-row month', (tester) async {
    await expectGolden(
      tester,
      CalendarViewData(year: 2024, month: 12, today: today),
      'six_rows',
    );
  });

  testWidgets('at 160% text size', (tester) async {
    await expectGolden(
      tester,
      CalendarViewData(
        year: 2024,
        month: 5,
        today: today,
        periodStarts: {aDate(2024, 5, 3)},
        loggedDays: {aDate(2024, 5, 4)},
      ),
      'large_text',
      textScale: 1.6,
    );
  });
}
