import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
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

  testWidgets('opens on the current month', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('May'), findsOneWidget);
  });

  testWidgets('marks a stored period start', (tester) async {
    final handle = tester.ensureSemantics();
    await database.logDao.addPeriodStart(aDate(2024, 5, 3));
    await pumpPage(tester);

    expect(
      find.bySemanticsLabel(RegExp(r'May 3, 2024.*Period start')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('marks a stored entry', (tester) async {
    final handle = tester.ensureSemantics();
    await database.logDao.saveEntry(
      aDayEntry(date: aDate(2024, 5, 9), flow: FlowIntensity.light),
    );
    await pumpPage(tester);

    expect(
      find.bySemanticsLabel(RegExp(r'May 9, 2024.*Logged')),
      findsOneWidget,
    );
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
    expect(
      find.bySemanticsLabel(RegExp(r'May \d+, 2024.*Estimated period')),
      findsWidgets,
    );
    handle.dispose();
  });

  testWidgets('steps to another month and reads it', (tester) async {
    final handle = tester.ensureSemantics();
    await database.logDao.addPeriodStart(aDate(2024, 4, 11));
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('April'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'April 11, 2024.*Period start')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('logging a past day from the grid persists it', (tester) async {
    await pumpPage(tester);

    // The 6th: in the past, and unique in a Sunday-first May 2024 grid.
    await tester.tap(
      find
          .ancestor(of: find.text('6'), matching: find.byType(InkResponse))
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await database.logDao.allPeriodStarts(), [aDate(2024, 5, 6)]);
  });

  testWidgets('the grid shows it immediately afterwards', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(tester);

    await tester.tap(
      find
          .ancestor(of: find.text('6'), matching: find.byType(InkResponse))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp(r'May 6, 2024.*Period start')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
