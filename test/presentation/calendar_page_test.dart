import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/calendar/calendar_page.dart';
import 'package:period/presentation/providers.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// The calendar against a real database.
///
/// This is the loop CLAUDE.md section 4 is built around and that the app could
/// not close until now: a day in the past is tapped, corrected, and every
/// estimate drawn from it moves. Until this screen existed the schema supported
/// retroactive correction and the interface could not reach it.
void main() {
  late AppDatabase db;
  late FixedClock clock;

  setUp(() {
    db = aDatabase();
    clock = FixedClock(aDate(2024, 5, 17));
  });
  // No tearDown closing the database: pumpWithDatabase closes it in the right
  // order relative to unmounting the widget tree.

  Future<void> pumpCalendar(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const CalendarPage(),
      database: db,
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
    );
  }

  /// Opens the sheet for the day named by [label] and saves it.
  ///
  /// [toggleStart] flips the period-start switch, so marking and unmarking are
  /// the same call. The day is named by its spoken label, which changes as the
  /// day changes -- a day that has become a period start says so.
  Future<void> log(
    WidgetTester tester,
    String label, {
    bool toggleStart = false,
  }) async {
    await tester.tap(find.bySemanticsLabel(label));
    await settleDatabase(tester);
    if (toggleStart) {
      await tester.tap(find.byType(Switch));
      await settleDatabase(tester);
    }
    await tester.tap(find.text('Save'));
    await settleDatabase(tester);
  }

  testWidgets('opens on the month containing today', (tester) async {
    await pumpCalendar(tester);
    expect(find.text('May 2024'), findsOneWidget);
    expect(find.bySemanticsLabel('May 17, 2024, Today'), findsOneWidget);
  });

  testWidgets(
    'a fresh month says nothing is logged rather than looking broken',
    (tester) async {
      await pumpCalendar(tester);
      expect(find.text('Nothing logged this month'), findsOneWidget);
    },
  );

  testWidgets('the sheet opens for the day that was tapped, not for today', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await tester.tap(find.bySemanticsLabel('May 3, 2024'));
    await settleDatabase(tester);

    expect(find.text('Log Fri, May 3'), findsOneWidget);
  });

  testWidgets('a past day can be logged, and says so afterwards', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await log(tester, 'May 3, 2024');

    expect(find.text('Saved'), findsOneWidget);
    expect(find.bySemanticsLabel('May 3, 2024, Logged'), findsOneWidget);
    expect(await db.logDao.entryOn(aDate(2024, 5, 3)), isNotNull);
  });

  testWidgets('a period start recorded days late lands on the right day', (
    tester,
  ) async {
    await pumpCalendar(tester);
    // The case the screen exists for: she bled on the 12th and is only opening
    // the app on the 17th.
    await log(tester, 'May 12, 2024', toggleStart: true);

    expect(await db.logDao.allPeriodStarts(), [aDate(2024, 5, 12)]);
    expect(find.bySemanticsLabel('May 12, 2024, Period start'), findsOneWidget);
  });

  testWidgets('a start on the wrong day can be moved to the right one', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await log(tester, 'May 12, 2024', toggleStart: true);
    // Corrected: it was actually the 10th. The day is named by what it has
    // become, because that is what a screen reader now reads out.
    await log(tester, 'May 12, 2024, Period start', toggleStart: true);
    await log(tester, 'May 10, 2024', toggleStart: true);

    expect(await db.logDao.allPeriodStarts(), [aDate(2024, 5, 10)]);
  });

  testWidgets('unmarking a start offers undo, and the undo works', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await log(tester, 'May 12, 2024', toggleStart: true);
    await log(tester, 'May 12, 2024, Period start', toggleStart: true);

    expect(await db.logDao.allPeriodStarts(), isEmpty);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settleDatabase(tester);
    expect(await db.logDao.allPeriodStarts(), [aDate(2024, 5, 12)]);
  });

  testWidgets('an ordinary save offers no undo', (tester) async {
    await pumpCalendar(tester);
    await log(tester, 'May 3, 2024');

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('days logged out of order still read back in order', (
    tester,
  ) async {
    await pumpCalendar(tester);
    await log(tester, 'May 12, 2024', toggleStart: true);
    await log(tester, 'May 2, 2024', toggleStart: true);
    await log(tester, 'May 7, 2024', toggleStart: true);

    expect(await db.logDao.allPeriodStarts(), [
      aDate(2024, 5, 2),
      aDate(2024, 5, 7),
      aDate(2024, 5, 12),
    ]);
  });

  testWidgets('a future day cannot be logged', (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.bySemanticsLabel('May 20, 2024'));
    await settleDatabase(tester);

    expect(find.byType(Switch), findsNothing);
    expect(await db.logDao.entryOn(aDate(2024, 5, 20)), isNull);
  });

  group('moving between months', () {
    testWidgets('back and forward again returns to where it started', (
      tester,
    ) async {
      await pumpCalendar(tester);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await settleDatabase(tester);
      expect(find.text('April 2024'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await settleDatabase(tester);
      expect(find.text('May 2024'), findsOneWidget);
    });

    testWidgets('a day logged in a previous month is still marked there', (
      tester,
    ) async {
      await db.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 4, 9), flow: FlowIntensity.medium),
      );
      await pumpCalendar(tester);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await settleDatabase(tester);
      expect(find.bySemanticsLabel('April 9, 2024, Logged'), findsOneWidget);
    });

    testWidgets('every month back to a fresh install is reachable', (
      tester,
    ) async {
      await pumpCalendar(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byIcon(Icons.chevron_left));
        await settleDatabase(tester);
      }
      expect(find.text('December 2023'), findsOneWidget);
    });
  });

  testWidgets('a corrected start moves the estimate drawn on the calendar', (
    tester,
  ) async {
    // Two cycles of 28 days, which is enough to predict from.
    for (final start in [aDate(2024, 3, 20), aDate(2024, 4, 17)]) {
      await db.logDao.addPeriodStart(start);
    }
    await db.logDao.addPeriodStart(aDate(2024, 5, 15));
    await pumpCalendar(tester);

    // 15 May + 28 days is 12 June, so the window sits in the following month.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await settleDatabase(tester);
    expect(
      find.bySemanticsLabel('June 12, 2024, Estimated period'),
      findsOneWidget,
    );

    // She corrects the last start: it was the 13th, not the 15th. Nothing
    // derived was stored, so the estimate follows on the next build.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await settleDatabase(tester);
    await log(tester, 'May 15, 2024, Period start', toggleStart: true);
    await log(tester, 'May 13, 2024', toggleStart: true);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await settleDatabase(tester);
    expect(
      find.bySemanticsLabel('June 10, 2024, Estimated period'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('June 12, 2024'), findsOneWidget);
  });
}
