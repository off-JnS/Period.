import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:period/presentation/analysis/analysis_page.dart';
import 'package:period/presentation/providers.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// The analysis screen against a real database.
///
/// The assertion that matters most is the last one: a start date corrected
/// after the fact changes every number here. Section 4 forbids storing any of
/// them precisely so that stays true, and this is where it is checked.
void main() {
  late AppDatabase db;

  setUp(() => db = aDatabase());

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(FixedClock(aDate(2024, 5, 17))),
  ];

  Future<void> pumpAnalysis(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const AnalysisPage(),
      database: db,
      overrides: overrides(),
      surface: const Size(400, 1400),
    );
  }

  /// Three 28-day cycles, with four days of flow logged from each start.
  Future<void> givenThreeCycles() async {
    for (final start in [
      aDate(2024, 2, 21),
      aDate(2024, 3, 20),
      aDate(2024, 4, 17),
      aDate(2024, 5, 15),
    ]) {
      await db.logDao.addPeriodStart(start);
      for (var day = 0; day < 4; day++) {
        await db.logDao.saveEntry(
          aDayEntry(date: start.addDays(day), flow: FlowIntensity.medium),
        );
      }
    }
  }

  testWidgets('a fresh install says so rather than showing a blank', (
    tester,
  ) async {
    await pumpAnalysis(tester);

    expect(find.text('Nothing logged yet'), findsOneWidget);
  });

  testWidgets('the numbers come from what was actually logged', (tester) async {
    await givenThreeCycles();
    await pumpAnalysis(tester);

    // Three completed cycles of 28 days; the fourth is in progress and has no
    // length yet, so it is not counted.
    expect(find.text('28 days'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text('4 days'), findsWidgets);
  });

  testWidgets('period duration comes from the run of logged flow', (
    tester,
  ) async {
    await db.logDao.addPeriodStart(aDate(2024, 4, 17));
    await db.logDao.addPeriodStart(aDate(2024, 5, 15));
    for (var day = 0; day < 6; day++) {
      await db.logDao.saveEntry(
        aDayEntry(
          date: aDate(2024, 4, 17).addDays(day),
          flow: FlowIntensity.light,
        ),
      );
    }
    await pumpAnalysis(tester);

    expect(find.textContaining('6 days bleeding'), findsOneWidget);
  });

  testWidgets(
    'a start with no flow logged does not shorten the typical period',
    (tester) async {
      // She marked five starts and logged flow for two of them. Averaging the
      // unlogged ones in as zeros would report a typical period of 3 days for
      // someone whose periods have always run 5 -- a number she has never had,
      // presented as a fact about her body.
      //
      // Two unlogged starts, not one, and that matters: a median over
      // [0, 5, 5] is still 5, so a single zero cannot show the difference. The
      // first version of this test was green against the bug for that reason.
      for (final start in [
        aDate(2024, 1, 24),
        aDate(2024, 2, 21),
        aDate(2024, 3, 20),
        aDate(2024, 4, 17),
        aDate(2024, 5, 15),
      ]) {
        await db.logDao.addPeriodStart(start);
      }
      for (final start in [aDate(2024, 1, 24), aDate(2024, 2, 21)]) {
        for (var day = 0; day < 5; day++) {
          await db.logDao.saveEntry(
            aDayEntry(date: start.addDays(day), flow: FlowIntensity.medium),
          );
        }
      }

      await pumpAnalysis(tester);

      expect(
        find.text('5 days'),
        findsWidgets,
        reason: 'the unlogged start was averaged in as a zero',
      );
      expect(find.text('3 days'), findsNothing);
    },
  );

  testWidgets('symptoms are tallied and translated, not shown as keys', (
    tester,
  ) async {
    await db.logDao.addPeriodStart(aDate(2024, 4, 17));
    for (var day = 0; day < 3; day++) {
      await db.logDao.saveEntry(
        aDayEntry(
          date: aDate(2024, 4, 17).addDays(day),
          symptoms: {const Symptom(key: 'cramps')},
        ),
      );
    }
    await pumpAnalysis(tester);

    expect(find.text('Cramps'), findsOneWidget);
    expect(find.text('cramps'), findsNothing, reason: 'the raw key is showing');
  });

  testWidgets('the screen is the same in a mode where estimates are off', (
    tester,
  ) async {
    // docs/cycle-logic.md section 6: pure description may be shown in every
    // mode. This is the one screen that is not gated on predictionsEnabled,
    // and the reason is that none of it predicts anything.
    await givenThreeCycles();
    await db.settingsDao.writeCycleSettings(
      const CycleSettings(mode: CycleMode.pregnancy),
    );
    await pumpAnalysis(tester);

    expect(find.text('28 days'), findsWidgets);
    expect(find.text('Nothing logged yet'), findsNothing);
  });

  testWidgets('a corrected start date changes every number', (tester) async {
    // Section 4's whole promise. Nothing here is stored, so moving a start
    // moves the statistics with it.
    await db.logDao.addPeriodStart(aDate(2024, 3, 20));
    await db.logDao.addPeriodStart(aDate(2024, 4, 17));
    await pumpAnalysis(tester);
    expect(find.text('28 days'), findsWidgets);

    // It was actually the 15th, not the 17th: a 26-day cycle.
    await db.logDao.removePeriodStart(aDate(2024, 4, 17));
    await db.logDao.addPeriodStart(aDate(2024, 4, 15));
    container(tester).invalidate(periodStartsProvider);
    await settleDatabase(tester);

    expect(find.text('26 days'), findsWidgets);
    expect(find.text('28 days'), findsNothing);
  });

  testWidgets('an unreadable settings row does not break this screen', (
    tester,
  ) async {
    // The analysis screen never reads the cycle mode, so a row that makes
    // SettingsDao throw must not reach it. If this ever starts failing, this
    // screen has grown a dependency on settings it does not need.
    await givenThreeCycles();
    await db.customStatement(
      'INSERT INTO settings (key, value) VALUES (?, ?)',
      ['cycle_mode', 'a_mode_from_the_future'],
    );
    await pumpAnalysis(tester);

    expect(find.text('28 days'), findsWidgets);
  });
}

/// The provider container behind the pumped tree.
ProviderContainer container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AnalysisPage)));
