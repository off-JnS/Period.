import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:period/data/reminders.dart';
import 'package:period/domain/models/reminder_schedule.dart';
import 'package:period/domain/models/reminder_time.dart';
import 'package:timezone/timezone.dart' as tz;

import '../support/dates.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

/// One recorded call to `zonedSchedule`.
class _Scheduled {
  _Scheduled(this.id, this.when, this.repeat);

  final int id;
  final tz.TZDateTime when;
  final DateTimeComponents? repeat;

  @override
  String toString() => 'id $id at $when repeating $repeat';
}

/// What the reminder seam actually asks the plugin to do.
///
/// The plugin is mocked, so **nothing here proves a notification ever appears**
/// -- see docs/verification.md. What it does prove is the part that is ours:
/// which series exist, when each one starts, and how each repeats. Those are
/// silent failures on a device, where the only symptom is a reminder that does
/// not arrive on some days and no way to tell which.
void main() {
  late _MockPlugin plugin;
  late LocalNotificationReminders reminders;
  late List<_Scheduled> scheduled;

  setUpAll(() {
    registerFallbackValue(tz.TZDateTime.utc(2024));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
    registerFallbackValue(UILocalNotificationDateInterpretation.wallClockTime);
  });

  setUp(() {
    plugin = _MockPlugin();
    reminders = LocalNotificationReminders(plugin: plugin);
    scheduled = [];

    when(() => plugin.cancelAll()).thenAnswer((_) async {});
    when(() => plugin.cancel(any())).thenAnswer((_) async {});
    when(
      () => plugin.zonedSchedule(
        any(),
        any(),
        any(),
        any(),
        any(),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        uiLocalNotificationDateInterpretation: any(
          named: 'uiLocalNotificationDateInterpretation',
        ),
        matchDateTimeComponents: any(named: 'matchDateTimeComponents'),
      ),
    ).thenAnswer((invocation) async {
      scheduled.add(
        _Scheduled(
          invocation.positionalArguments[0] as int,
          invocation.positionalArguments[3] as tz.TZDateTime,
          invocation.namedArguments[#matchDateTimeComponents]
              as DateTimeComponents?,
        ),
      );
    });
  });

  // 2024-05-17 was a Friday, which is ISO weekday 5.
  final friday = aDate(2024, 5, 17);
  const morning = ReminderTime(9, 0);

  Future<void> apply(ReminderSchedule schedule, {ReminderTime? now}) =>
      reminders.applySchedule(
        schedule,
        today: friday,
        now: now ?? morning,
        title: 'Reminder',
        body: 'Open when you have a moment.',
      );

  group('turning it off', () {
    test('schedules nothing and clears what was there', () async {
      await apply(const ReminderSchedule());

      verify(() => plugin.cancelAll()).called(1);
      expect(scheduled, isEmpty);
    });

    test('on with no weekday chosen also schedules nothing', () async {
      // Distinct from off in the interface; identical in effect here, and
      // worth pinning so a change to one does not silently change the other.
      await apply(const ReminderSchedule(enabled: true, weekdays: {}));

      verify(() => plugin.cancelAll()).called(1);
      expect(scheduled, isEmpty);
    });
  });

  group('a daily reminder', () {
    test('is one series, not seven', () async {
      await apply(const ReminderSchedule(enabled: true));

      expect(scheduled, hasLength(1));
      expect(scheduled.single.id, dailyReminderId);
      expect(scheduled.single.repeat, DateTimeComponents.time);
    });

    test('starts today when the time has not passed', () async {
      await apply(const ReminderSchedule(enabled: true), now: morning);

      // The whole point of the id and the start date being separate: a daily
      // series seeded from a weekday rather than from today would not fire
      // until that weekday came round, leaving up to six silent days.
      expect(scheduled.single.when.day, 17);
      expect(scheduled.single.when.hour, 20);
      expect(scheduled.single.when.minute, 0);
    });

    test('starts tomorrow once today has gone by', () async {
      await apply(
        const ReminderSchedule(enabled: true),
        now: const ReminderTime(21, 0),
      );

      expect(scheduled.single.when.day, 18);
    });

    test(
      'does not use a weekday id, which skipToday would then miss',
      () async {
        await apply(const ReminderSchedule(enabled: true));

        expect(scheduled.single.id, isNot(inInclusiveRange(1, 7)));
      },
    );
  });

  group('a weekly reminder', () {
    test('is one series per chosen day, keyed by weekday', () async {
      await apply(const ReminderSchedule(enabled: true, weekdays: {1, 3, 5}));

      expect(scheduled.map((s) => s.id).toSet(), {1, 3, 5});
      for (final entry in scheduled) {
        expect(entry.repeat, DateTimeComponents.dayOfWeekAndTime);
      }
    });

    test('each series starts on its own weekday', () async {
      await apply(const ReminderSchedule(enabled: true, weekdays: {1, 3, 5}));

      for (final entry in scheduled) {
        // TZDateTime.weekday is ISO, as CycleDate.weekday is.
        expect(
          entry.when.weekday,
          entry.id,
          reason: 'series ${entry.id} starts on the wrong day',
        );
      }
    });

    test('today counts when its time is still to come', () async {
      // Friday is 5, and it is only morning.
      await apply(
        const ReminderSchedule(enabled: true, weekdays: {5}),
        now: morning,
      );

      expect(scheduled.single.when.day, 17);
    });

    test('today wraps a whole week once its time has gone', () async {
      await apply(
        const ReminderSchedule(enabled: true, weekdays: {5}),
        now: const ReminderTime(21, 0),
      );

      expect(scheduled.single.when.day, 24);
    });

    test('six days is still six weekly series, not a daily one', () async {
      // The boundary. Only all seven collapses into one series; five or six
      // must stay separate or the days she deselected would be reminded on.
      await apply(
        const ReminderSchedule(enabled: true, weekdays: {1, 2, 3, 4, 5, 6}),
      );

      expect(scheduled, hasLength(6));
      for (final entry in scheduled) {
        expect(entry.repeat, DateTimeComponents.dayOfWeekAndTime);
      }
    });

    test('a weekday outside 1..7 is dropped rather than scheduled', () async {
      await apply(const ReminderSchedule(enabled: true, weekdays: {0, 3, 9}));

      expect(scheduled.map((s) => s.id), [3]);
    });

    test(
      'seven entries are not seven days if one of them is nonsense',
      () async {
        // The trap behind counting the stored set rather than the valid one.
        // This has seven entries and six real days, so counting raw would call
        // it daily -- and she would be reminded on the Sunday she deselected.
        await apply(
          const ReminderSchedule(
            enabled: true,
            weekdays: {1, 2, 3, 4, 5, 6, 9},
          ),
        );

        expect(scheduled, hasLength(6));
        expect(scheduled.map((s) => s.id).toSet(), {1, 2, 3, 4, 5, 6});
        for (final entry in scheduled) {
          expect(entry.repeat, DateTimeComponents.dayOfWeekAndTime);
        }
      },
    );
  });

  group('the wall-clock time', () {
    test('is the time she chose, on the day it falls', () async {
      await apply(
        const ReminderSchedule(
          enabled: true,
          time: ReminderTime(7, 5),
          weekdays: {3},
        ),
      );

      expect(scheduled.single.when.hour, 7);
      expect(scheduled.single.when.minute, 5);
    });

    test(
      'survives a month boundary as a calendar day, not an offset',
      () async {
        // Wednesday 2024-05-22 is the next 3 after Friday the 17th; pushing the
        // schedule to the end of the month checks the date is built rather than
        // added to.
        await reminders.applySchedule(
          const ReminderSchedule(enabled: true, weekdays: {3}),
          today: aDate(2024, 4, 29),
          now: morning,
          title: 'Reminder',
          body: 'body',
        );

        expect(scheduled.single.when.year, 2024);
        expect(scheduled.single.when.month, 5);
        expect(scheduled.single.when.day, 1);
      },
    );
  });

  group('skipping a day already logged', () {
    test('cancels today and puts the series straight back', () async {
      const schedule = ReminderSchedule(enabled: true, weekdays: {1, 3, 5});
      await reminders.skipToday(
        schedule,
        today: friday,
        title: 'Reminder',
        body: 'body',
      );

      // Cancelled and rescheduled. Cancelling alone would end the series: she
      // logs once and is never reminded on a Friday again.
      verify(() => plugin.cancel(5)).called(1);
      expect(scheduled, hasLength(1));
      expect(scheduled.single.id, 5);
      expect(scheduled.single.when.day, 24, reason: 'a week on from Friday');
    });

    test('a daily reminder comes back tomorrow, not next week', () async {
      await reminders.skipToday(
        const ReminderSchedule(enabled: true),
        today: friday,
        title: 'Reminder',
        body: 'body',
      );

      verify(() => plugin.cancel(dailyReminderId)).called(1);
      expect(scheduled.single.id, dailyReminderId);
      expect(scheduled.single.when.day, 18);
    });

    test('does nothing on a day she never chose', () async {
      // Friday is 5, and this schedule is Mondays only.
      await reminders.skipToday(
        const ReminderSchedule(enabled: true, weekdays: {1}),
        today: friday,
        title: 'Reminder',
        body: 'body',
      );

      verifyNever(() => plugin.cancel(any()));
      expect(scheduled, isEmpty);
    });

    test('does nothing while reminders are off', () async {
      await reminders.skipToday(
        const ReminderSchedule(),
        today: friday,
        title: 'Reminder',
        body: 'body',
      );

      verifyNever(() => plugin.cancel(any()));
      expect(scheduled, isEmpty);
    });
  });

  group('cancelling everything', () {
    test('goes through to the plugin', () async {
      await reminders.cancelAll();
      verify(() => plugin.cancelAll()).called(1);
    });
  });
}
