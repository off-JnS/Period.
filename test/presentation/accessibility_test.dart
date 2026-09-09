import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/domain/logic/logged_summary.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';
import 'package:period/presentation/calendar/month_grid.dart';
import 'package:period/presentation/lock/lock_screen.dart';
import 'package:period/presentation/settings/passphrase_dialog.dart';
import 'package:period/presentation/settings/settings_screen.dart';
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

  group('settings', () {
    Widget screen(SettingsViewData data) => SettingsScreen(
      data: data,
      onModeChanged: (_) {},
      onPredictionsOptInChanged: ({required optedIn}) {},
      onFertileWindowChanged: ({required optedIn}) {},
      onDeleteEverything: () {},
      onExportBackup: () {},
      onRestoreBackup: () {},
      onAppLockChanged: ({required enabled}) {},
    );

    testWidgets('light', (tester) async {
      await expectAccessible(tester, screen(const SettingsViewData()));
    });

    testWidgets('with the perimenopause opt-in showing', (tester) async {
      // The one row that appears conditionally, and so the one most likely to
      // be missed by a check that only ever sees the default screen.
      await expectAccessible(
        tester,
        screen(
          const SettingsViewData(
            cycle: CycleSettings(mode: CycleMode.perimenopause),
          ),
        ),
      );
    });

    testWidgets('dark', (tester) async {
      await expectAccessibleInDark(tester, screen(const SettingsViewData()));
    });
  });

  group('the history screen', () {
    final history = AnalysisViewData(
      cycles: [
        for (var i = 0; i < 4; i++)
          CycleSummary(
            startedOn: DateTime(2024, 1 + i, 3),
            lengthInDays: 27 + i,
            periodDays: 4,
          ),
      ],
      symptoms: const [SymptomTally(symptom: Symptom(key: 'cramps'), days: 9)],
      daysLogged: 20,
      typicalLength: 28,
      shortestLength: 27,
      longestLength: 30,
      typicalPeriodDays: 4,
    );

    testWidgets('light', (tester) async {
      await expectAccessible(tester, AnalysisScreen(data: history));
    });

    testWidgets('empty', (tester) async {
      await expectAccessible(
        tester,
        const AnalysisScreen(data: AnalysisViewData()),
      );
    });

    testWidgets('dark', (tester) async {
      await expectAccessibleInDark(tester, AnalysisScreen(data: history));
    });
  });

  testWidgets('the lock screen', (tester) async {
    // The one screen a user meets before she can do anything else.
    await expectAccessible(tester, LockScreen(onUnlock: () {}));
  });

  group('the passphrase dialogue', () {
    testWidgets('choosing one', (tester) async {
      await expectAccessible(
        tester,
        const Scaffold(body: PassphraseDialog(confirming: true)),
      );
    });

    testWidgets('entering one', (tester) async {
      await expectAccessible(
        tester,
        const Scaffold(body: PassphraseDialog(confirming: false)),
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

  group('the Today button never covers what it sits over', () {
    // A floating button is drawn on top of the list, so the list has to end
    // above it. Today reserves that space as bottom padding, and a number
    // chosen once by eye is exactly the kind of thing that stops being right
    // when the text grows, the locale changes, or the button gains a word.
    //
    // The thing being protected is the doctor hint's dismiss button, the last
    // control in the list. Covered, it cannot be tapped, and the hint cannot be
    // got rid of. Nothing else on the screen would look wrong.
    //
    // Checked to 3x because iOS accessibility text sizes go well past the 2x
    // Android tops out at, and 2x passing says nothing about 3x.
    final data = TodayViewData(
      cycleDay: 34,
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
    );

    for (final locale in ['en', 'de']) {
      for (final textScale in [1.0, 2.0, 3.0]) {
        testWidgets('$locale at ${textScale}x text', (tester) async {
          await pumpApp(
            tester,
            TodayScreen(data: data, onLogToday: () {}),
            locale: Locale(locale),
            textScale: textScale,
          );

          // Scrolled to the very end, which is the only place the two can meet.
          // A lazily built list reports a maxScrollExtent that grows as more of
          // it is built, so one jump lands short of the end and every
          // measurement taken there is wrong -- including, once, the
          // measurement that said this was broken. Jump until it stops moving.
          final position = tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position;
          var previous = -1.0;
          for (var i = 0; i < 20 && position.maxScrollExtent != previous; i++) {
            previous = position.maxScrollExtent;
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
          }
          expect(
            position.pixels,
            position.maxScrollExtent,
            reason: 'the list did not reach its end, so nothing below is true',
          );

          final button = tester.getRect(
            find.byType(FloatingActionButton),
          );
          final dismiss = tester.getRect(find.byType(TextButton).last);
          expect(
            dismiss.overlaps(button),
            isFalse,
            reason:
                'the log button covers the dismiss button at ${textScale}x in '
                '$locale: dismiss $dismiss, button $button',
          );
        });
      }
    }
  });
}
