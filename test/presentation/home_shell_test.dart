import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/home_shell.dart';
import 'package:period/presentation/profile/profile_page.dart';
import 'package:period/presentation/reminders/reminder_sync.dart';
import 'package:period/presentation/settings/settings_page.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fake_reminder_scheduler.dart';
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
    expect(tab('Profile'), findsOneWidget);
    // Settings opens from Profile rather than taking a tab.
    expect(tab('Settings'), findsNothing);
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

  testWidgets('a mode chosen on Profile applies on Today', (tester) async {
    await pumpShell(tester);
    await tester.tap(tab('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Pregnancy'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsLabel('Pregnancy'));
    await tester.pumpAndSettle();

    await tester.tap(tab('Today'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estimates are off during pregnancy'), findsOne);
  });

  testWidgets('Settings opens from Profile and keeps the tab bar', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(tab('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
  });

  group('reminders', () {
    late FakeReminderScheduler scheduler;

    Future<void> pumpWithReminders(WidgetTester tester) async {
      scheduler = FakeReminderScheduler();
      await pumpApp(
        tester,
        HomeShell(
          logDao: database.logDao,
          settingsDao: database.settingsDao,
          clock: FixedClock(today),
          reminderSync: ReminderSync(
            logDao: database.logDao,
            settingsDao: database.settingsDao,
            scheduler: scheduler,
            clock: FixedClock(today),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets('are scheduled when the app opens, in its language', (
      tester,
    ) async {
      await database.settingsDao.saveReminderSettings(
        const ReminderSettings(dailyLog: true),
      );
      await pumpWithReminders(tester);
      expect(scheduler.schedules, isNotEmpty);
      expect(scheduler.lastText, 'Reminder');
    });

    testWidgets('are rescheduled on returning to the app', (tester) async {
      await pumpWithReminders(tester);
      final before = scheduler.schedules.length;

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(scheduler.schedules.length, greaterThan(before));
    });

    testWidgets('are rescheduled after logging a day', (tester) async {
      await pumpWithReminders(tester);
      final before = scheduler.schedules.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(scheduler.schedules.length, greaterThan(before));
    });
  });
}
