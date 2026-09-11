import 'package:period/data/database/daos/settings_dao.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/reminder_schedule.dart';
import 'package:period/domain/models/reminder_time.dart';
import 'package:test/test.dart';

import '../support/database.dart';

/// What the app reads back out of the settings table.
///
/// The interesting tests are the two at the bottom. A value this build does not
/// understand must not quietly become a natural cycle, because natural is the
/// one mode that turns predictions *on*.
void main() {
  late AppDatabase db;

  setUp(() => db = aDatabase());
  tearDown(() => db.close());

  test('a fresh install is a natural cycle with predictions on', () async {
    final stored = await db.settingsDao.readSettings();

    expect(stored.cycle.mode, CycleMode.natural);
    expect(stored.cycle.predictionsOptedIn, isFalse);
    expect(stored.cycle.predictionsEnabled, isTrue);
    expect(stored.fertileWindowOptedIn, isFalse);
  });

  for (final mode in CycleMode.values) {
    test('${mode.name} survives a round trip', () async {
      await db.settingsDao.writeCycleSettings(CycleSettings(mode: mode));
      expect((await db.settingsDao.readSettings()).cycle.mode, mode);
    });
  }

  test('the perimenopause opt-in survives a round trip', () async {
    await db.settingsDao.writeCycleSettings(
      const CycleSettings(
        mode: CycleMode.perimenopause,
        predictionsOptedIn: true,
      ),
    );

    final stored = await db.settingsDao.readSettings();
    expect(stored.cycle.predictionsOptedIn, isTrue);
    expect(stored.cycle.predictionsEnabled, isTrue);
  });

  test('the fertile window opt-in survives a round trip', () async {
    await db.settingsDao.writeFertileWindowOptIn(optedIn: true);
    expect((await db.settingsDao.readSettings()).fertileWindowOptedIn, isTrue);

    await db.settingsDao.writeFertileWindowOptIn(optedIn: false);
    expect((await db.settingsDao.readSettings()).fertileWindowOptedIn, isFalse);
  });

  test('the app lock is off unless asked for, and round-trips', () async {
    // Section 9 makes the lock optional, which is also why the database key is
    // generated rather than derived from it: defaulting this on would be a
    // different app than the one CLAUDE.md describes.
    expect((await db.settingsDao.readSettings()).appLockEnabled, isFalse);

    await db.settingsDao.writeAppLockEnabled(enabled: true);
    expect((await db.settingsDao.readSettings()).appLockEnabled, isTrue);

    await db.settingsDao.writeAppLockEnabled(enabled: false);
    expect((await db.settingsDao.readSettings()).appLockEnabled, isFalse);
  });

  test('changing mode overwrites rather than accumulating rows', () async {
    await db.settingsDao.writeCycleSettings(
      const CycleSettings(mode: CycleMode.pregnancy),
    );
    await db.settingsDao.writeCycleSettings(
      const CycleSettings(mode: CycleMode.natural),
    );

    expect((await db.settingsDao.readSettings()).cycle.mode, CycleMode.natural);
  });

  test('opting out of predictions is stored, not just omitted', () async {
    await db.settingsDao.writeCycleSettings(
      const CycleSettings(
        mode: CycleMode.perimenopause,
        predictionsOptedIn: true,
      ),
    );
    await db.settingsDao.writeCycleSettings(
      const CycleSettings(mode: CycleMode.perimenopause),
    );

    final stored = await db.settingsDao.readSettings();
    expect(stored.cycle.predictionsOptedIn, isFalse);
    expect(stored.cycle.predictionsEnabled, isFalse);
  });

  group('a value this build does not understand', () {
    Future<void> storeRawMode(String value) => db.customStatement(
      'INSERT INTO settings (key, value) VALUES (?, ?)',
      [SettingKeys.cycleMode, value],
    );

    test('throws rather than falling back to a natural cycle', () async {
      // The scenario: a database written by a newer build, restored onto this
      // one. Falling back would mean natural, and natural enables predictions
      // -- so a pregnant user would silently get estimates she turned off.
      // Failing loudly puts the error panel on screen instead.
      await storeRawMode('lactational_amenorrhea');

      expect(db.settingsDao.readSettings(), throwsStateError);
    });

    test('the message says what it found and that it will not guess', () async {
      await storeRawMode('something_new');

      await expectLater(
        db.settingsDao.readSettings(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('something_new'), contains('will not guess')),
          ),
        ),
      );
    });

    test('an unreadable opt-in flag resolves to off, not on', () async {
      // Lenient where the mode is strict, and deliberately so: these flags are
      // opt-ins, so an unreadable one showing less than she asked for is the
      // safe direction. An unreadable *mode* is not, which is why it throws.
      await db.customStatement(
        'INSERT INTO settings (key, value) VALUES (?, ?)',
        [SettingKeys.fertileWindowOptedIn, 'yes'],
      );

      expect(
        (await db.settingsDao.readSettings()).fertileWindowOptedIn,
        isFalse,
      );
    });
  });

  group('the reminder schedule', () {
    Future<void> storeRaw(String key, String value) => db.customStatement(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      [key, value],
    );

    test('a fresh install has reminders off, every day, at 20:00', () async {
      // Off is what matters. The time and the days are only what a picker
      // would open on, and neither means anything until she turns it on.
      final stored = (await db.settingsDao.readSettings()).reminder;

      expect(stored.enabled, isFalse);
      expect(stored.time, const ReminderTime(20, 0));
      expect(stored.validWeekdays, {1, 2, 3, 4, 5, 6, 7});
    });

    test('round trips what she chose', () async {
      const schedule = ReminderSchedule(
        enabled: true,
        time: ReminderTime(7, 5),
        weekdays: {2, 4},
      );

      await db.settingsDao.writeReminderSchedule(schedule);
      final stored = (await db.settingsDao.readSettings()).reminder;

      expect(stored.enabled, isTrue);
      expect(stored.time, const ReminderTime(7, 5));
      expect(stored.validWeekdays, {2, 4});
    });

    test('stores the weekdays sorted, and drops the impossible ones', () async {
      // The insertion order here is deliberately neither sorted nor its
      // reverse: {3, 7, 1} would still read as '1,3,7' if the list were merely
      // reversed, and this test would pass against code that never sorted at
      // all. It was written that way first, and a mutation caught it.
      await db.settingsDao.writeReminderSchedule(
        const ReminderSchedule(enabled: true, weekdays: {3, 9, 7, 0, 1}),
      );

      final raw = await db.settingsDao.readAll();
      expect(raw[SettingKeys.reminderWeekdays], '1,3,7');
    });

    test('an unreadable time falls back rather than throwing', () async {
      // Lenient, like the opt-in flags and unlike the cycle mode. The worst it
      // can do is remind her at an hour she did not pick; it cannot turn on
      // something she turned off, which is what makes an unreadable mode throw.
      await storeRaw(SettingKeys.reminderTime, 'half past eight');

      expect(
        (await db.settingsDao.readSettings()).reminder.time,
        const ReminderTime(20, 0),
      );
    });

    test('an unreadable weekday list means nothing fires', () async {
      // The safe direction for an opt-in: less than she asked for, never a
      // notification on a day she never chose.
      await storeRaw(SettingKeys.reminderWeekdays, 'weekends,maybe');

      expect(
        (await db.settingsDao.readSettings()).reminder.validWeekdays,
        isEmpty,
      );
    });

    test('deselecting every day is honoured, not treated as unset', () async {
      // Absent means she has never chosen and defaults to daily. An empty
      // stored value means she deliberately cleared them, and reverting that to
      // daily would hand her back seven notifications she just removed.
      await storeRaw(SettingKeys.reminderWeekdays, '');

      expect(
        (await db.settingsDao.readSettings()).reminder.validWeekdays,
        isEmpty,
      );
    });

    test('a partly unreadable list keeps the days that are real', () async {
      await storeRaw(SettingKeys.reminderWeekdays, '1,x,5');

      expect((await db.settingsDao.readSettings()).reminder.validWeekdays, {
        1,
        5,
      });
    });
  });
}
