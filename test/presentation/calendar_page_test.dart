import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/calendar/calendar_page.dart';

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
    expect(find.text('Period May 3 – May 6 · 4 days'), findsOneWidget);
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
    expect(find.textContaining('Next period, estimated'), findsOneWidget);
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
    expect(find.textContaining('Fertile window'), findsNothing);

    await database.settingsDao.saveCycleSettings(
      const CycleSettings(fertileWindowOptedIn: true),
    );
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
    // The caveat travels with the marks, never behind a tap.
    expect(
      find.textContaining('Not suitable for preventing pregnancy'),
      findsWidgets,
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
}
