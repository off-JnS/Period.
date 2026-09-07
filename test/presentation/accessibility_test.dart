import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/presentation/calendar/month_grid.dart';
import 'package:period/presentation/today/log_entry_sheet.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// Flutter's own accessibility guidelines, run against every screen.
///
/// These were checked by hand once and then nothing kept them true. They belong
/// in the suite: CLAUDE.md section 9 is a promise about who can use this app,
/// and a promise nothing tests is a promise that quietly expires. The four
/// guidelines are tap target size on both platforms, text contrast, and whether
/// every tappable thing has a name a screen reader can read out.
void main() {
  Future<void> expectAccessible(WidgetTester tester, Widget screen) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, screen);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // Disposed here rather than in a teardown: the framework checks for leaked
    // handles before teardowns run.
    handle.dispose();
  }

  Future<void> expectAccessibleInDark(
    WidgetTester tester,
    Widget screen,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, screen, brightness: Brightness.dark);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }

  group('the calendar', () {
    final grid = MonthGrid.of(aDate(2024, 4, 1), firstWeekday: 1);
    final data = CalendarViewData(
      today: aDate(2024, 4, 15),
      periodStarts: {aDate(2024, 4, 3)},
      loggedDays: {aDate(2024, 4, 3), aDate(2024, 4, 4)},
      prediction: PredictedPeriod(
        earliest: aDate(2024, 4, 29),
        latest: aDate(2024, 5, 3),
      ),
    );
    Widget screen() => CalendarScreen(
      data: data,
      grid: grid,
      onSelectDay: (_) {},
      onPreviousMonth: () {},
      onNextMonth: () {},
    );

    testWidgets('light', (tester) async {
      await expectAccessible(tester, screen());
    });

    testWidgets('dark', (tester) async {
      await expectAccessibleInDark(tester, screen());
    });
  });

  group('today', () {
    Widget screen(TodayViewData data) =>
        TodayScreen(data: data, onLogToday: () {});

    testWidgets('a fresh install', (tester) async {
      await expectAccessible(
        tester,
        screen(
          const TodayViewData(prediction: NotEnoughCycles(have: 0, need: 2)),
        ),
      );
    });

    testWidgets('with everything on screen at once', (tester) async {
      await expectAccessible(
        tester,
        screen(
          TodayViewData(
            cycleDay: 17,
            typicalCycleLength: 28,
            prediction: PredictedPeriod(
              earliest: aDate(2024, 4, 26),
              latest: aDate(2024, 4, 30),
            ),
            fertileWindow: FertileWindowEstimate(
              earliest: aDate(2024, 4, 6),
              latest: aDate(2024, 4, 20),
            ),
            showDoctorHint: true,
          ),
        ),
      );
    });

    testWidgets('dark', (tester) async {
      await expectAccessibleInDark(
        tester,
        screen(
          const TodayViewData(prediction: NotEnoughCycles(have: 0, need: 2)),
        ),
      );
    });
  });

  testWidgets('the logging sheet', (tester) async {
    // Inside a Scaffold, as it is in the app: a bottom sheet is drawn on a
    // surface, and checking its contrast against nothing checks nothing.
    await expectAccessible(
      tester,
      Scaffold(body: LogEntrySheet(date: aDate(2024, 4, 15))),
    );
  });
}
