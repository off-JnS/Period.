import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/logic/reminders.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/reminders/reminder_sync.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fake_reminder_scheduler.dart';
import '../support/fixed_clock.dart';

/// Through the real DAOs: what matters is that what is stored turns into the
/// right schedule.
void main() {
  late AppDatabase database;
  late FakeReminderScheduler scheduler;
  late ReminderSync sync;
  final today = aDate(2024, 5, 17);

  setUp(() {
    database = aDatabase();
    scheduler = FakeReminderScheduler();
    sync = ReminderSync(
      logDao: database.logDao,
      settingsDao: database.settingsDao,
      scheduler: scheduler,
      clock: FixedClock(today),
    );
  });
  tearDown(() => database.close());

  Future<void> run() => sync.sync(text: 'Reminder', channelName: 'Reminders');

  Future<void> logRegularHistory() async {
    // Starts every 28 days, the last on 3 May: the window opens around 31 May.
    for (final start in regularPeriodStarts(
      from: aDate(2024, 2, 9),
      length: 28,
      count: 4,
    )) {
      await database.logDao.addPeriodStart(start);
    }
  }

  test('contraception reminders follow the method in her profile', () async {
    await database.settingsDao.saveReminderSettings(
      ReminderSettings(ring: true, ringInserted: today, pill: true),
    );
    await database.settingsDao.saveProfile(
      const Profile(contraception: ContraceptionMethod.ring),
    );
    await run();
    expect(scheduler.current!.map((r) => r.kind).toSet(), {
      ReminderKind.ringOut,
      ReminderKind.ringIn,
    });

    // A new method silences the old one's reminders at the next sync.
    await database.settingsDao.saveProfile(
      const Profile(contraception: ContraceptionMethod.combinedPill),
    );
    await run();
    expect(scheduler.current!.map((r) => r.kind).toSet(), {ReminderKind.pill});
  });

  test('with every reminder off, clears the schedule', () async {
    await run();
    expect(scheduler.current, isEmpty);
  });

  test('schedules the period reminder from the stored history', () async {
    await logRegularHistory();
    await database.settingsDao.saveReminderSettings(
      const ReminderSettings(periodComing: true, daysBefore: 3),
    );
    await run();

    final reminder = scheduler.current!.single;
    expect(reminder.kind, ReminderKind.periodComing);
    expect(reminder.day.isAfter(today), isTrue);
    expect(scheduler.lastText, 'Reminder');
  });

  test('a mode with predictions off drops the period reminder', () async {
    await logRegularHistory();
    await database.settingsDao.saveReminderSettings(
      const ReminderSettings(periodComing: true),
    );
    await database.settingsDao.saveCycleSettings(
      const CycleSettings(mode: CycleMode.pregnancy),
    );
    await run();
    expect(scheduler.current, isEmpty);
  });

  test('a new period start moves the reminder', () async {
    await logRegularHistory();
    await database.settingsDao.saveReminderSettings(
      const ReminderSettings(periodComing: true),
    );
    await run();
    final before = scheduler.current!.single.day;

    // She corrects the last start two days later (section 4: nothing stored
    // to go stale, so the next sync simply computes the new date).
    await database.logDao.removePeriodStart(aDate(2024, 5, 3));
    await database.logDao.addPeriodStart(aDate(2024, 5, 5));
    await run();

    expect(scheduler.current!.single.day, before.addDays(2));
  });

  test('daily reminders need no history at all', () async {
    await database.settingsDao.saveReminderSettings(
      const ReminderSettings(dailyLog: true),
    );
    await run();
    expect(scheduler.current, hasLength(dailyReminderHorizonDays));
  });

  test('quick successive syncs finish in order', () async {
    await database.settingsDao.saveReminderSettings(
      const ReminderSettings(dailyLog: true),
    );
    final first = run();
    await database.settingsDao.saveReminderSettings(const ReminderSettings());
    final second = run();
    await Future.wait([first, second]);
    // The last word is the latest settings: nothing scheduled.
    expect(scheduler.current, isEmpty);
  });

  test('a failure does not escape to the screen that asked', () async {
    await database.close();
    await expectLater(run(), completes);
    database = aDatabase();
  });
}
