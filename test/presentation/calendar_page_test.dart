import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/calendar/calendar_page.dart';
import 'package:period/presentation/log/log_entry_screen.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// The calendar against a real database, for the same reason `TodayPage` is:
/// what matters is that logging a day changes what the next read shows.
void main() {
  late AppDatabase database;
  final today = aDate(2024, 5, 17);

  setUp(() => database = aDatabase());
  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester, {Locale? locale}) async {
    await pumpApp(
      tester,
      CalendarPage(
        logDao: database.logDao,
        settingsDao: database.settingsDao,
        clock: FixedClock(today),
      ),
      locale: locale ?? const Locale('en'),
      surface: const Size(420, 1000),
    );
  }

  Finder day(String pattern) => find.bySemanticsLabel(RegExp(pattern));

  testWidgets('opens on the current month', (tester) async {
    await pumpPage(tester);
    expect(find.text('May'), findsOneWidget);
  });

  testWidgets('marks a stored period start', (tester) async {
    final handle = tester.ensureSemantics();
    await database.logDao.addPeriodStart(aDate(2024, 5, 3));
    await pumpPage(tester);

    expect(day(r'^May 3, 2024.*Period start'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('marks every day of a period, and says how long it was', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await database.logDao.addPeriodStart(aDate(2024, 5, 3));
    for (var i = 0; i < 4; i++) {
      await database.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 3 + i), flow: FlowIntensity.medium),
      );
    }
    await pumpPage(tester);

    expect(day(r'^May 5, 2024.*Period'), findsOneWidget);
    expect(day(r'^May 7, 2024.*Period'), findsNothing);
    handle.dispose();
  });

  testWidgets('marks a stored entry', (tester) async {
    final handle = tester.ensureSemantics();
    await database.logDao.saveEntry(
      aDayEntry(date: aDate(2024, 5, 9), note: 'tired'),
    );
    await pumpPage(tester);

    expect(day(r'^May 9, 2024.*Logged'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('shows the estimated window once it can compute one', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final start in regularPeriodStarts(
      from: aDate(2024, 2, 26),
      length: 28,
      count: 3,
    )) {
      await database.logDao.addPeriodStart(start);
    }
    await pumpPage(tester);

    // Last start 22 April plus a 28-day median lands the window in late May.
    expect(day(r'^May \d+, 2024.*Estimated period'), findsWidgets);
    handle.dispose();
  });

  testWidgets('shows the fertile window only when she opted in', (
    tester,
  ) async {
    for (final start in regularPeriodStarts(
      from: aDate(2024, 2, 26),
      length: 28,
      count: 3,
    )) {
      await database.logDao.addPeriodStart(start);
    }
    await pumpPage(tester);
    await tester.tap(find.byIcon(CupertinoIcons.info_circle));
    await tester.pumpAndSettle();
    expect(find.text('Estimated fertile window'), findsNothing);

    await database.settingsDao.saveCycleSettings(
      const CycleSettings(fertileWindowOptedIn: true),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
    // The caveat comes with the legend now that the window is drawn.
    await tester.tap(find.byIcon(CupertinoIcons.info_circle));
    await tester.pumpAndSettle();
    expect(find.text('Estimated fertile window'), findsOneWidget);
    expect(
      find.textContaining('Not suitable for preventing pregnancy'),
      findsOneWidget,
    );
  });

  testWidgets('scrolls back to an earlier month and shows what is there', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await database.logDao.addPeriodStart(aDate(2023, 11, 11));
    await pumpPage(tester);

    await tester.scrollUntilVisible(
      find.text('November 2023'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(day(r'^November 11, 2023.*Period start'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Today brings the current month back', (tester) async {
    await pumpPage(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('May'), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('May'), findsOneWidget);
  });

  Future<void> logMay6(WidgetTester tester) async {
    await tester.tap(day(r'^May 6, 2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('logging a past day from the grid persists it', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(tester);
    await logMay6(tester);

    expect(await database.logDao.allPeriodStarts(), [aDate(2024, 5, 6)]);
    handle.dispose();
  });

  testWidgets('the grid shows it immediately afterwards', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(tester);
    await logMay6(tester);

    expect(day(r'^May 6, 2024.*Period start'), findsOneWidget);
    handle.dispose();
  });

  group('tapping a day', () {
    testWidgets('shows what was logged, without editing anything', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await database.logDao.addPeriodStart(aDate(2024, 5, 3));
      await database.logDao.saveEntry(
        aDayEntry(
          date: aDate(2024, 5, 4),
          flow: FlowIntensity.heavy,
          symptoms: {aSymptom(key: 'cramps')},
          note: 'long day',
        ),
      );
      await pumpPage(tester);
      await tester.tap(day(r'^May 4, 2024'));
      await tester.pumpAndSettle();

      expect(find.text('Saturday, May 4'), findsOneWidget);
      expect(find.text('Cycle day 2'), findsOneWidget);
      expect(find.text('Flow: Heavy'), findsOneWidget);
      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('long day'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      // Only looking: no entry sheet yet.
      expect(find.text('Save'), findsNothing);
      handle.dispose();
    });

    testWidgets('Edit opens the day with what was logged', (tester) async {
      final handle = tester.ensureSemantics();
      await database.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 4), note: 'long day'),
      );
      await pumpPage(tester);
      await tester.tap(day(r'^May 4, 2024'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
      expect(
        tester.widget<LogEntryScreen>(find.byType(LogEntryScreen)).entry?.note,
        'long day',
      );
      handle.dispose();
    });

    testWidgets('a future day shows its estimate but cannot be edited', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      for (final start in regularPeriodStarts(
        from: aDate(2024, 2, 26),
        length: 28,
        count: 3,
      )) {
        await database.logDao.addPeriodStart(start);
      }
      await pumpPage(tester);
      await tester.tap(day(r'^May 20, 2024'));
      await tester.pumpAndSettle();

      expect(find.text('Monday, May 20'), findsOneWidget);
      expect(find.text('Estimated period'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Add entry'), findsNothing);
      expect(find.textContaining('Cycle day'), findsNothing);
      handle.dispose();
    });
  });

  testWidgets('shows a heart on a day she recorded sex, not on a "no"', (
    tester,
  ) async {
    await database.logDao.saveEntry(
      aDayEntry(
        date: aDate(2024, 5, 9),
        symptoms: {aSymptom(key: 'sex.protected')},
      ),
    );
    await database.logDao.saveEntry(
      aDayEntry(
        date: aDate(2024, 5, 10),
        symptoms: {aSymptom(key: 'sex.none')},
      ),
    );
    await pumpPage(tester);
    expect(find.byIcon(CupertinoIcons.heart_fill), findsOneWidget);
  });
}
