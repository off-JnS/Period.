import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/reminder_time.dart';
import 'package:period/presentation/app_shell.dart';
import 'package:period/presentation/providers.dart';
import 'package:period/presentation/settings/settings_page.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/reminders.dart';
import '../support/widgets.dart';

/// Settings against a real database, and the loop this slice exists to close.
///
/// Before this screen, every user on hormonal contraception, every pregnant
/// user and every perimenopausal user was shown confident estimates that
/// docs/cycle-logic.md section 6 says must never be given. The logic to refuse
/// them was written and tested; nothing could reach it. The tests below are
/// what "it is reachable now" means.
void main() {
  late AppDatabase db;
  late Directory documents;
  late FixedClock clock;
  late FakeReminders reminders;

  setUp(() {
    db = aDatabase();
    documents = Directory.systemTemp.createTempSync('period_documents');
    addTearDown(() => documents.deleteSync(recursive: true));
    clock = FixedClock(aDate(2024, 5, 17));
    reminders = FakeReminders();
  });

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    documentsDirectoryProvider.overrideWithValue(documents),
    remindersProvider.overrideWithValue(reminders),
  ];

  Future<void> pumpSettings(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const SettingsPage(),
      database: db,
      overrides: overrides(),
    );
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const AppShell(),
      database: db,
      overrides: overrides(),
    );
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settleDatabase(tester);
  }

  /// Two 28-day cycles and one in progress: enough history to predict from, so
  /// an estimate really would be shown if the mode did not stop it.
  Future<void> givenEnoughHistory() async {
    for (final start in [
      aDate(2024, 3, 20),
      aDate(2024, 4, 17),
      aDate(2024, 5, 15),
    ]) {
      await db.logDao.addPeriodStart(start);
    }
  }

  testWidgets('opens on a natural cycle for a fresh install', (tester) async {
    await pumpSettings(tester);
    expect(
      tester
          .widget<RadioGroup<CycleMode>>(find.byType(RadioGroup<CycleMode>))
          .groupValue,
      CycleMode.natural,
    );
  });

  testWidgets('a chosen mode is stored', (tester) async {
    await pumpSettings(tester);
    await choose(tester, 'Pregnant');

    expect(
      (await db.settingsDao.readSettings()).cycle.mode,
      CycleMode.pregnancy,
    );
  });

  testWidgets('a chosen mode survives leaving the screen', (tester) async {
    await pumpSettings(tester);
    await choose(tester, 'Hormonal contraception');

    // Rebuilt from scratch, reading the database again.
    await pumpSettings(tester);
    expect(
      tester
          .widget<RadioGroup<CycleMode>>(find.byType(RadioGroup<CycleMode>))
          .groupValue,
      CycleMode.hormonalContraception,
    );
  });

  group('the mode actually reaches the estimate', () {
    testWidgets('a natural cycle is given one', (tester) async {
      await givenEnoughHistory();
      await pumpShell(tester);

      // 15 May plus a 28-day median, so the window sits in mid-June.
      expect(find.textContaining('Jun '), findsWidgets);
    });

    testWidgets('pregnancy is not, and Today says why', (tester) async {
      await givenEnoughHistory();
      await pumpShell(tester);

      await tester.tap(find.text('Settings'));
      await settleDatabase(tester);
      await choose(tester, 'Pregnant');

      await tester.tap(find.text('Today'));
      await settleDatabase(tester);

      expect(find.textContaining('Jun '), findsNothing);
      expect(
        find.textContaining('Estimates are off during pregnancy'),
        findsOneWidget,
      );
    });

    testWidgets('contraception is not, and Today says why', (tester) async {
      await givenEnoughHistory();
      await pumpShell(tester);

      await tester.tap(find.text('Settings'));
      await settleDatabase(tester);
      await choose(tester, 'Hormonal contraception');

      await tester.tap(find.text('Today'));
      await settleDatabase(tester);

      expect(
        find.textContaining('withdrawal bleed follows your regimen'),
        findsOneWidget,
      );
    });

    testWidgets('perimenopause is off until she asks, then on', (tester) async {
      await givenEnoughHistory();
      await pumpShell(tester);

      await tester.tap(find.text('Settings'));
      await settleDatabase(tester);
      await choose(tester, 'Perimenopause');

      await tester.tap(find.text('Today'));
      await settleDatabase(tester);
      expect(find.textContaining('Jun '), findsNothing);

      await tester.tap(find.text('Settings'));
      await settleDatabase(tester);
      await choose(tester, 'Show estimates anyway');

      await tester.tap(find.text('Today'));
      await settleDatabase(tester);
      expect(find.textContaining('Jun '), findsWidgets);
    });

    testWidgets('the opt-in does not follow her out of perimenopause', (
      tester,
    ) async {
      await pumpSettings(tester);
      await choose(tester, 'Perimenopause');
      await choose(tester, 'Show estimates anyway');
      expect(
        (await db.settingsDao.readSettings()).cycle.predictionsOptedIn,
        isTrue,
      );

      // Left set, it would silently turn estimates on again the moment she
      // came back -- a choice she made about a different situation.
      await choose(tester, 'Pregnant');
      await choose(tester, 'Perimenopause');

      final stored = await db.settingsDao.readSettings();
      expect(stored.cycle.predictionsOptedIn, isFalse);
      expect(stored.cycle.predictionsEnabled, isFalse);
    });
  });

  group('the fertile window', () {
    testWidgets('appears on Today only once asked for', (tester) async {
      await givenEnoughHistory();
      await pumpShell(tester);
      expect(find.text('Estimated fertile window'), findsNothing);

      await tester.tap(find.text('Settings'));
      await settleDatabase(tester);
      await choose(tester, 'Show the fertile window estimate');

      await tester.tap(find.text('Today'));
      await settleDatabase(tester);
      expect(find.text('Estimated fertile window'), findsOneWidget);
    });

    testWidgets('the choice is stored', (tester) async {
      await pumpSettings(tester);
      await choose(tester, 'Show the fertile window estimate');

      expect(
        (await db.settingsDao.readSettings()).fertileWindowOptedIn,
        isTrue,
      );
    });
  });

  group('the log reminder', () {
    /// Scrolls the reminder switch into view and taps it.
    Future<void> toggleReminder(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.text('Remind me to log'),
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(ListView),
        ),
        const Offset(0, -100),
      );
      await settleDatabase(tester);
      await tester.tap(find.text('Remind me to log'));
      await settleDatabase(tester);
    }

    testWidgets('asks the operating system before turning it on', (
      tester,
    ) async {
      await pumpSettings(tester);
      await toggleReminder(tester);

      expect(reminders.permissionRequests, 1);
      expect((await db.settingsDao.readSettings()).reminder.enabled, isTrue);
    });

    testWidgets('a refusal stores nothing and schedules nothing', (
      tester,
    ) async {
      // The switch has to stay off. A stored "on" that can never show anything
      // is a setting that lies, and she would have no way to tell.
      reminders.granted = false;
      await pumpSettings(tester);
      await toggleReminder(tester);

      expect((await db.settingsDao.readSettings()).reminder.enabled, isFalse);
      expect(reminders.applied, isEmpty);
      expect(find.textContaining('Notifications are turned off'), findsOne);
    });

    testWidgets('schedules from the clock, not from a stored timestamp', (
      tester,
    ) async {
      clock.date = aDate(2024, 5, 17);
      clock.time = const ReminderTime(9, 0);
      await pumpSettings(tester);
      await toggleReminder(tester);

      final applied = reminders.lastApplied!;
      expect(applied.today, aDate(2024, 5, 17));
      expect(applied.now, const ReminderTime(9, 0));
    });

    testWidgets('the notification text says nothing about a cycle', (
      tester,
    ) async {
      // Section 9. This is the one string in the app a stranger holding her
      // phone can read without unlocking it.
      await pumpSettings(tester);
      await toggleReminder(tester);

      final applied = reminders.lastApplied!;
      for (final word in [
        'cycle',
        'period',
        'fertile',
        'ovulation',
        'log',
        'day',
      ]) {
        expect(
          '${applied.title} ${applied.body}'.toLowerCase(),
          isNot(contains(word)),
          reason: '"$word" would be readable on a locked screen',
        );
      }
    });

    testWidgets('turning it off again does not ask a second time', (
      tester,
    ) async {
      await pumpSettings(tester);
      await toggleReminder(tester);
      await toggleReminder(tester);

      expect(reminders.permissionRequests, 1);
      expect((await db.settingsDao.readSettings()).reminder.enabled, isFalse);
      // Still applied, so whatever was scheduled is cleared rather than left
      // firing after she switched it off.
      expect(reminders.lastApplied!.schedule.enabled, isFalse);
    });

    testWidgets('deselecting a weekday stores it and reschedules', (
      tester,
    ) async {
      await pumpSettings(tester);
      await toggleReminder(tester);

      // Every day is selected by default, so the first tap removes one.
      await tester.tap(find.widgetWithText(FilterChip, 'Wed'));
      await settleDatabase(tester);

      expect((await db.settingsDao.readSettings()).reminder.weekdays, {
        1,
        2,
        4,
        5,
        6,
        7,
      });
      expect(reminders.lastApplied!.schedule.weekdays, {1, 2, 4, 5, 6, 7});
    });

    testWidgets('the weekday chooser is not colour alone', (tester) async {
      // Section 9. A screen reader gets the day and its state in words, and a
      // sighted user gets a checkmark as well as a fill.
      await pumpSettings(tester);
      await toggleReminder(tester);

      expect(find.bySemanticsLabel('Wednesday, selected'), findsOne);
      await tester.tap(find.widgetWithText(FilterChip, 'Wed'));
      await settleDatabase(tester);
      expect(find.bySemanticsLabel('Wednesday, not selected'), findsOne);
    });
  });

  group('deleting everything', () {
    /// Scrolls the delete row into view and taps it.
    ///
    /// It sits at the foot of a list that has grown, and a ListView does not
    /// build what is below the fold. Scoped to the settings list because inside
    /// the shell every tab is mounted and there is more than one scrollable.
    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.text('Delete all data'),
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(ListView),
        ),
        const Offset(0, -100),
      );
      await settleDatabase(tester);
      await tester.tap(find.text('Delete all data'));
      await settleDatabase(tester);
    }

    Future<void> confirmDelete(WidgetTester tester) async {
      await openDeleteDialog(tester);
      await tester.tap(find.text('Delete everything'));
      await settleDatabase(tester);
    }

    testWidgets('empties every table', (tester) async {
      await givenEnoughHistory();
      await db.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 16), note: 'a note'),
      );
      await db.settingsDao.writeCycleSettings(
        const CycleSettings(mode: CycleMode.pregnancy),
      );

      await pumpSettings(tester);
      await confirmDelete(tester);

      expect(await db.logDao.allPeriodStarts(), isEmpty);
      expect(await db.logDao.entryOn(aDate(2024, 5, 16)), isNull);
      expect(find.text('Everything deleted'), findsOneWidget);
    });

    testWidgets('takes the migration copies beside the database too', (
      tester,
    ) async {
      // The screen has to call the erase, not just empty the tables. Dropping
      // rows was all it did, and section 5's `<db>.backup-v<n>` copies sat
      // beside the database holding the same entries -- which is not the fresh
      // install the confirmation promises.
      await givenEnoughHistory();
      final copy = File('${documents.path}/$databaseFileName.backup-v1')
        ..writeAsStringSync('her entries, from before the last migration');

      await pumpSettings(tester);
      await confirmDelete(tester);

      expect(copy.existsSync(), isFalse);
      expect(migrationBackupsIn(documents), isEmpty);
    });

    testWidgets('takes the cycle mode with it, back to a fresh install', (
      tester,
    ) async {
      // Deliberate, and said in the confirmation: "delete all data" that left a
      // setting behind would not be what it says. It does mean a pregnant user
      // who deletes returns to a natural cycle with estimates on.
      await pumpSettings(tester);
      await choose(tester, 'Pregnant');
      await confirmDelete(tester);

      expect(
        (await db.settingsDao.readSettings()).cycle.mode,
        CycleMode.natural,
      );
      // Back to the top first. The list is lazy and long enough that the mode
      // picker is no longer built after scrolling down to the delete tile, so
      // without this the finder reports nothing and the test fails describing a
      // bug that is not there.
      await tester.dragUntilVisible(
        find.byType(RadioGroup<CycleMode>),
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(ListView),
        ),
        const Offset(0, 100),
      );
      expect(
        tester
            .widget<RadioGroup<CycleMode>>(find.byType(RadioGroup<CycleMode>))
            .groupValue,
        CycleMode.natural,
      );
    });

    testWidgets('Today goes back to asking for entries', (tester) async {
      await givenEnoughHistory();
      await pumpShell(tester);

      await tester.tap(find.text('Settings'));
      await settleDatabase(tester);
      await confirmDelete(tester);

      await tester.tap(find.text('Today'));
      await settleDatabase(tester);
      expect(find.text('No cycle yet'), findsOneWidget);
    });

    testWidgets('cancelling keeps everything', (tester) async {
      await givenEnoughHistory();
      await pumpSettings(tester);

      await openDeleteDialog(tester);
      await tester.tap(find.text('Cancel'));
      await settleDatabase(tester);

      expect(await db.logDao.allPeriodStarts(), hasLength(3));
    });
  });

  testWidgets('an unreadable stored mode shows the error, not a guess', (
    tester,
  ) async {
    // A database written by a newer build. Guessing would mean natural, which
    // turns estimates on -- so the screen refuses rather than showing her a
    // mode she never chose and letting her save over the one she did.
    await db.customStatement(
      'INSERT INTO settings (key, value) VALUES (?, ?)',
      ['cycle_mode', 'something_this_build_has_never_heard_of'],
    );

    await pumpSettings(tester);
    expect(find.byType(RadioGroup<CycleMode>), findsNothing);
    expect(find.textContaining('Try again'), findsOneWidget);
  });
}
