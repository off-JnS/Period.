import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/views.dart';
import '../support/dates.dart';
import '../support/widgets.dart';

/// Golden tests for the Today screen, as CLAUDE.md section 7 requires.
///
/// These are the app's only visual review surface: nobody has to install
/// Flutter or run an emulator to see what a change did to a screen, and an
/// unintended visual change fails here rather than reaching a user.
///
/// Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
///
/// A diff in these files is a change to what a person sees. Read it before
/// accepting it.
void main() {
  // The cycle these goldens describe began on 3 April, which is what puts the
  // estimate below at the end of the month.
  //
  // The date is on screen now that the app bar carries it, so it has to agree
  // with the rest of the picture. Derived from the cycle day rather than fixed:
  // a golden showing "Wednesday, April 24" above "Day 12" is a picture of a bug
  // that is not there, and a reviewer cannot tell that from one that is.
  final cycleStart = aDate(2024, 4, 3);
  CycleDate dayOfCycle(int? day) => cycleStart.addDays((day ?? 1) - 1);

  final predicted = PredictedPeriod(
    earliest: aDate(2024, 4, 26),
    latest: aDate(2024, 4, 30),
  );
  final fertile = FertileWindowEstimate(
    earliest: aDate(2024, 4, 6),
    latest: aDate(2024, 4, 20),
  );

  Future<void> expectGolden(
    WidgetTester tester,
    TodayViewData data,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      // A callback so the log button renders: it is the only way into the app,
      // and a golden without it would not show what the user actually sees.
      TodayScreen(data: data, onLogToday: () {}),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
    );
    await expectLater(
      find.byType(TodayScreen),
      matchesGoldenFile('goldens/today_$name.png'),
    );
  }

  testWidgets('a fresh install', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(1),
        prediction: NotEnoughCycles(have: 0, need: 2),
      ),
      'fresh_install',
    );
  });

  testWidgets('an estimate', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(22),
        cycleDay: 22,
        typicalCycleLength: 28,
        prediction: predicted,
      ),
      'estimate',
    );
  });

  testWidgets('an estimate with the fertile window opted in', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(12),
        cycleDay: 12,
        typicalCycleLength: 28,
        prediction: predicted,
        fertileWindow: fertile,
      ),
      'fertile_window',
    );
  });

  testWidgets('cycles too variable to estimate', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(31),
        cycleDay: 31,
        prediction: CyclesTooVariable(9),
      ),
      'too_variable',
    );
  });

  testWidgets('predictions off during pregnancy', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(1),
        prediction: PredictionsDisabled(CycleMode.pregnancy),
      ),
      'pregnancy',
    );
  });

  testWidgets('predictions off on hormonal contraception', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(9),
        cycleDay: 9,
        prediction: PredictionsDisabled(CycleMode.hormonalContraception),
      ),
      'contraception',
    );
  });

  testWidgets('the doctor hint', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(34),
        cycleDay: 34,
        typicalCycleLength: 28,
        prediction: predicted,
        showDoctorHint: true,
      ),
      'doctor_hint',
    );
  });

  testWidgets('a cycle running past its usual length', (tester) async {
    // Must not look like a cycle finishing exactly on time. The ring shows a
    // second lap in a different colour, and the day number says it in words.
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(34),
        cycleDay: 34,
        typicalCycleLength: 28,
        prediction: predicted,
      ),
      'overdue',
    );
  });

  testWidgets('running past the usual length', (tester) async {
    // The ring alone shows this in a second colour; section 9 needs words too.
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(34),
        cycleDay: 34,
        typicalCycleLength: 28,
        prediction: predicted,
      ),
      'late',
    );
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(22),
        cycleDay: 22,
        typicalCycleLength: 28,
        prediction: predicted,
        fertileWindow: fertile,
      ),
      'dark',
      brightness: Brightness.dark,
    );
  });

  testWidgets('German, which runs about a third longer than English', (
    tester,
  ) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(22),
        cycleDay: 22,
        typicalCycleLength: 28,
        prediction: PredictionsDisabled(CycleMode.perimenopause),
      ),
      'german',
      locale: const Locale('de'),
    );
  });

  testWidgets('at 200% text size', (tester) async {
    await expectGolden(
      tester,
      aTodayView(
        today: dayOfCycle(22),
        cycleDay: 22,
        typicalCycleLength: 28,
        prediction: predicted,
      ),
      'large_text',
      textScale: 2,
    );
  });
}
