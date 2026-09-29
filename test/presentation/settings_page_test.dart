import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/lock/app_lock.dart';
import 'package:period/presentation/reminders/reminder_sync.dart';
import 'package:period/presentation/settings/settings_page.dart';
import 'package:period/presentation/settings/settings_screen.dart';
import 'package:period/presentation/settings/reminders_screen.dart';
import 'package:period/domain/models/profile.dart';

import '../support/fake_authenticator.dart';
import '../support/fake_reminder_scheduler.dart';
import '../support/fixed_clock.dart';
import '../support/dates.dart';

import '../support/database.dart';
import '../support/widgets.dart';

/// Through the real DAO, so what is checked is that a tap is actually stored.
void main() {
  late AppDatabase database;

  setUp(() => database = aDatabase());
  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester) =>
      pumpApp(tester, SettingsPage(settingsDao: database.settingsDao));

  testWidgets('opens on what is stored', (tester) async {
    await database.settingsDao.saveAppPreferences(
      const AppPreferences(appearance: AppearanceChoice.dark),
    );
    await pumpPage(tester);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Dark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Dark')),
      isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
    );
  });

  testWidgets('no longer holds the cycle mode, which is on Profile', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Your situation'), findsNothing);
  });

  testWidgets('a chosen appearance is stored, then handed to the app', (
    tester,
  ) async {
    final applied = <AppPreferences>[];
    await pumpApp(
      tester,
      SettingsPage(
        settingsDao: database.settingsDao,
        onPreferencesChanged: applied.add,
      ),
    );
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Dark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsLabel('Dark'));
    await tester.pumpAndSettle();

    const expected = AppPreferences(appearance: AppearanceChoice.dark);
    expect(await database.settingsDao.appPreferences(), expected);
    expect(applied, [expected]);
  });

  group('the app lock switch', () {
    late FakeAuthenticator auth;
    late AppLock lock;

    setUp(() {
      auth = FakeAuthenticator();
      lock = AppLock(
        authenticator: auth,
        enabled: false,
        save: database.settingsDao.saveAppLockEnabled,
      );
    });
    tearDown(() => lock.dispose());

    Future<void> pumpWithLock(WidgetTester tester) async {
      await pumpApp(
        tester,
        SettingsPage(settingsDao: database.settingsDao, appLock: lock),
      );
      await tester.scrollUntilVisible(
        find.text('Lock app'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('turning it on asks for the owner, then stores it', (
      tester,
    ) async {
      await pumpWithLock(tester);
      await tester.tap(find.text('Lock app'));
      await tester.pumpAndSettle();

      expect(auth.prompts, 1);
      expect(await database.settingsDao.appLockEnabled(), isTrue);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Lock app'),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('a failed confirmation leaves it off', (tester) async {
      auth.succeeds = false;
      await pumpWithLock(tester);
      await tester.tap(find.text('Lock app'));
      await tester.pumpAndSettle();

      expect(await database.settingsDao.appLockEnabled(), isFalse);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Lock app'),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('without a device passcode it says what to do', (tester) async {
      auth.available = false;
      await pumpWithLock(tester);
      await tester.tap(find.text('Lock app'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Set a device passcode'), findsOneWidget);
      expect(await database.settingsDao.appLockEnabled(), isFalse);
    });

    testWidgets('is absent without a lock to control', (tester) async {
      await pumpApp(tester, SettingsPage(settingsDao: database.settingsDao));
      expect(find.text('Lock app'), findsNothing);
    });
  });

  group('reminders', () {
    late FakeReminderScheduler scheduler;
    late int affected;

    setUp(() {
      scheduler = FakeReminderScheduler();
      affected = 0;
    });

    Future<void> pumpWithReminders(WidgetTester tester) async {
      await pumpApp(
        tester,
        SettingsPage(
          settingsDao: database.settingsDao,
          reminderSync: ReminderSync(
            logDao: database.logDao,
            settingsDao: database.settingsDao,
            scheduler: scheduler,
            clock: FixedClock(aDate(2024, 5, 17)),
          ),
          onScheduleAffected: () => affected++,
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      // Their own page, opened from a row.
      await tester.scrollUntilVisible(
        find.byKey(SettingsKeys.reminders),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SettingsKeys.reminders));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets('the first reminder turned on asks permission, then saves', (
      tester,
    ) async {
      await pumpWithReminders(tester);
      await tester.tap(find.text('Daily reminder to log'));
      await tester.pumpAndSettle();

      expect(scheduler.permissionRequests, 1);
      expect(
        await database.settingsDao.reminderSettings(),
        const ReminderSettings(dailyLog: true),
      );
      expect(affected, 1);
    });

    testWidgets('refused permission leaves it off and says why', (
      tester,
    ) async {
      scheduler.grants = false;
      await pumpWithReminders(tester);
      await tester.tap(find.text('Daily reminder to log'));
      await tester.pumpAndSettle();

      expect((await database.settingsDao.reminderSettings()).dailyLog, isFalse);
      expect(find.textContaining('Notifications are turned off'), findsOne);
      expect(affected, 0);
    });

    testWidgets('a second reminder does not ask again', (tester) async {
      await database.settingsDao.saveReminderSettings(
        const ReminderSettings(dailyLog: true),
      );
      await pumpWithReminders(tester);
      await tester.tap(find.text('Before my period'));
      await tester.pumpAndSettle();
      expect(scheduler.permissionRequests, 0);
    });

    testWidgets('her method from Profile brings its reminder, saved', (
      tester,
    ) async {
      await database.settingsDao.saveProfile(
        const Profile(contraception: ContraceptionMethod.progestinPill),
      );
      await pumpWithReminders(tester);
      expect(find.text('Contraception: Progestin-only pill'), findsOneWidget);

      await tester.tap(find.byKey(RemindersKeys.methodSwitch));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(scheduler.permissionRequests, 1);
      expect((await database.settingsDao.reminderSettings()).pill, isTrue);
      expect(find.text('Take your pill'), findsWidgets);
      expect(affected, 1);

      // Back in Settings, the row says reminders are on.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('On'), findsOneWidget);
    });
  });

  group('delete all data', () {
    late List<(String, String)> erased;

    setUp(() => erased = []);

    Future<void> pumpWithErase(WidgetTester tester, {AppLock? lock}) async {
      await pumpApp(
        tester,
        SettingsPage(
          settingsDao: database.settingsDao,
          appLock: lock,
          onEraseEverything: (done, failed) async => erased.add((done, failed)),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('says plainly that it cannot be undone', (tester) async {
      await pumpWithErase(tester);
      expect(find.textContaining("can't be undone"), findsOneWidget);
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all data?'), findsOneWidget);
      expect(find.textContaining('cannot be recovered'), findsOneWidget);
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      await pumpWithErase(tester);
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(erased, isEmpty);
    });

    testWidgets('confirming deletes, with messages in her language', (
      tester,
    ) async {
      await pumpWithErase(tester);
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      expect(erased, [
        (
          'All data deleted',
          'Your data could not be deleted. Nothing was changed.',
        ),
      ]);
    });

    testWidgets('with the lock on, a failed Face ID stops it', (tester) async {
      final auth = FakeAuthenticator();
      final lock = AppLock(
        authenticator: auth,
        enabled: true,
        save: ({required enabled}) async {},
      );
      addTearDown(lock.dispose);
      await lock.unlock(reason: 'r');
      auth.succeeds = false;

      await pumpWithErase(tester, lock: lock);
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();

      expect(auth.prompts, 2);
      expect(erased, isEmpty);
    });

    testWidgets('is absent without a way to delete', (tester) async {
      await pumpApp(tester, SettingsPage(settingsDao: database.settingsDao));
      expect(find.text('Delete all data'), findsNothing);
    });
  });

  group('home-screen widget', () {
    testWidgets('is offered only where there is a widget', (tester) async {
      await pumpApp(tester, SettingsPage(settingsDao: database.settingsDao));
      expect(find.text('Show details'), findsNothing);
    });

    testWidgets('details are off by default, and saved when turned on', (
      tester,
    ) async {
      var affected = 0;
      await pumpApp(
        tester,
        SettingsPage(
          settingsDao: database.settingsDao,
          offerWidget: true,
          onScheduleAffected: () => affected++,
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Show details'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('only the day number'), findsOneWidget);

      await tester.tap(find.text('Show details'));
      await tester.pumpAndSettle();
      expect(await database.settingsDao.widgetDetailed(), isTrue);
      expect(affected, 1);
      expect(find.textContaining('readable by anyone'), findsOneWidget);
    });
  });
}
