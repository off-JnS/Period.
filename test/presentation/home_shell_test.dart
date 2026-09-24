import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/presentation/home_shell.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/widgets.dart';

/// Covers the tab bar that holds the three top-level screens.
void main() {
  late AppDatabase database;
  final today = aDate(2024, 5, 17);

  setUp(() => database = aDatabase());
  tearDown(() => database.close());

  Future<void> pumpShell(WidgetTester tester) => pumpApp(
    tester,
    HomeShell(
      logDao: database.logDao,
      settingsDao: database.settingsDao,
      clock: FixedClock(today),
    ),
  );

  Finder tab(String label) => find.descendant(
    of: find.byType(CupertinoTabBar),
    matching: find.text(label),
  );

  testWidgets('opens on Today', (tester) async {
    await pumpShell(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('labels every tab in words, not only with an icon', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(tab('Today'), findsOneWidget);
    expect(tab('Calendar'), findsOneWidget);
    expect(tab('Your cycles'), findsOneWidget);
    expect(tab('Settings'), findsOneWidget);
  });

  testWidgets('switches between the three screens', (tester) async {
    await pumpShell(tester);

    await tester.tap(tab('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(TodayScreen), findsNothing);

    await tester.tap(tab('Your cycles'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisScreen), findsOneWidget);

    await tester.tap(tab('Today'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('shows a day logged elsewhere when coming back to Today', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(tab('Calendar'));
    await tester.pumpAndSettle();

    // Written behind the screen's back, as logging from the calendar does.
    await tester.runAsync(() => database.logDao.addPeriodStart(today));

    await tester.tap(tab('Today'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Cycle day 1'), findsOneWidget);
  });

  testWidgets('a mode chosen in Settings applies on Today', (tester) async {
    await pumpShell(tester);
    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Pregnancy'));
    await tester.pumpAndSettle();

    await tester.tap(tab('Today'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estimates are off during pregnancy'), findsOne);
  });
}
