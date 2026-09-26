import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// Golden tests for the calendar, as CLAUDE.md section 7 requires.
///
/// These carry more weight here than on the Today screen. Section 9's rule that
/// no state is told by colour alone is a claim about what the grid *looks* like,
/// and a person reviewing these images is the only thing that can confirm the
/// filled band, the dashed band, the plain band, the ring and the dot really
/// are distinguishable from one another.
///
/// Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
void main() {
  final today = aDate(2024, 5, 17);

  // A period that ran 3–7 May, logged days scattered, today on the 17th, the
  // fertile window mid-month and the estimate crossing into June.
  final everything = CalendarViewData(
    today: today,
    periodStarts: {aDate(2024, 4, 5), aDate(2024, 5, 3)},
    flowByDay: {
      for (var d = 5; d <= 9; d++) aDate(2024, 4, d): FlowIntensity.medium,
      for (var d = 3; d <= 7; d++) aDate(2024, 5, d): FlowIntensity.medium,
    },
    loggedDays: {
      for (var d = 3; d <= 7; d++) aDate(2024, 5, d),
      aDate(2024, 5, 11),
      aDate(2024, 5, 14),
      today,
    },
    sexDays: {aDate(2024, 5, 11), aDate(2024, 5, 5)},
    predicted: PredictedPeriod(
      earliest: aDate(2024, 5, 29),
      latest: aDate(2024, 6, 2),
    ),
    fertileWindow: FertileWindowEstimate(
      earliest: aDate(2024, 5, 12),
      latest: aDate(2024, 5, 19),
    ),
  );

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
      surface: const Size(420, 900),
    );
    await expectLater(
      find.byType(CalendarScreen),
      matchesGoldenFile('goldens/calendar_$name.png'),
    );
  }

  testWidgets('nothing logged', (tester) async {
    await expectGolden(tester, CalendarViewData(today: today), 'empty');
  });

  testWidgets('every marker at once', (tester) async {
    await expectGolden(tester, everything, 'markers');
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(tester, everything, 'dark', brightness: Brightness.dark);
  });

  testWidgets('German, which starts the week on Monday', (tester) async {
    await expectGolden(
      tester,
      everything,
      'german',
      locale: const Locale('de'),
    );
  });

  testWidgets('a six-row month', (tester) async {
    // June 2024 starts on a Saturday, so a Sunday-first grid needs six rows.
    await expectGolden(
      tester,
      CalendarViewData(today: aDate(2024, 6, 10)),
      'six_rows',
    );
  });

  testWidgets('at 160% text size', (tester) async {
    await expectGolden(tester, everything, 'large_text', textScale: 1.6);
  });
}
