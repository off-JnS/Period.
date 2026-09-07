import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/presentation/calendar/month_grid.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// Golden tests for the calendar, as CLAUDE.md section 7 requires.
///
/// The four states are drawn with four different features rather than four
/// colours, which is a claim only a picture can really check. Regenerate
/// deliberately, never reflexively:
///
///     flutter test --update-goldens
///
/// A diff in these files is a change to what a person sees. Read it before
/// accepting it.
void main() {
  final today = aDate(2024, 4, 15);
  // A month with something of everything in it: a period recorded at the start,
  // today part-way through, and an estimated window running off the end into
  // the days that belong to May.
  final busy = CalendarViewData(
    today: today,
    periodStarts: {aDate(2024, 4, 3)},
    loggedDays: {
      aDate(2024, 4, 3),
      aDate(2024, 4, 4),
      aDate(2024, 4, 5),
      aDate(2024, 4, 11),
    },
    prediction: PredictedPeriod(
      earliest: aDate(2024, 4, 29),
      latest: aDate(2024, 5, 3),
    ),
  );

  Future<void> expectGolden(
    WidgetTester tester,
    CalendarViewData data,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    // Sunday-first, as an English reader expects; the German golden below is
    // the one that proves the other convention is drawn correctly too.
    int firstWeekday = 7,
  }) async {
    await pumpApp(
      tester,
      CalendarScreen(
        data: data,
        grid: MonthGrid.of(aDate(2024, 4, 1), firstWeekday: firstWeekday),
        // Callbacks so the arrows and the day cells render as they do in the
        // app; a golden of a screen with everything disabled shows nobody
        // anything useful.
        onSelectDay: (_) {},
        onPreviousMonth: () {},
        onNextMonth: () {},
      ),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
    );
    await expectLater(
      find.byType(CalendarScreen),
      matchesGoldenFile('goldens/calendar_$name.png'),
    );
  }

  testWidgets('a month with a period, entries and an estimate', (tester) async {
    await expectGolden(tester, busy, 'month');
  });

  testWidgets('a month with nothing in it', (tester) async {
    await expectGolden(tester, CalendarViewData(today: today), 'empty');
  });

  testWidgets('German, starting the week on Monday', (tester) async {
    await expectGolden(
      tester,
      busy,
      'german',
      locale: const Locale('de'),
      firstWeekday: 1,
    );
  });

  testWidgets('dark', (tester) async {
    await expectGolden(tester, busy, 'dark', brightness: Brightness.dark);
  });

  testWidgets('at twice the text size', (tester) async {
    await expectGolden(tester, busy, 'large_text', textScale: 2);
  });
}
