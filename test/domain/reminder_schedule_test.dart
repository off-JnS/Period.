import 'package:period/domain/logic/reminder_schedule.dart';
import 'package:period/domain/models/reminder_schedule.dart';
import 'package:period/domain/models/reminder_time.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

/// Reminder scheduling, per docs/cycle-logic.md section 7.
///
/// Pure Dart on the plain VM: no binding, no device, no clock. Every case
/// states its own day and time rather than mocking time, which is what CLAUDE.md
/// section 3 keeps the [Clock] abstraction for.
void main() {
  // 2024-05-17 was a Friday. Stated once here because most of what follows is
  // about which weekday a date lands on, and a reader should not have to work
  // that out per test.
  final friday = aDate(2024, 5, 17);
  const eightPm = ReminderTime(20, 0);
  const morning = ReminderTime(9, 0);

  ReminderSchedule daily({ReminderTime time = eightPm}) =>
      ReminderSchedule(enabled: true, time: time);

  ReminderSchedule onWeekdays(Set<int> weekdays) =>
      ReminderSchedule(enabled: true, time: eightPm, weekdays: weekdays);

  group('when there is nothing to schedule', () {
    test('reminders she never turned on', () {
      expect(
        nextReminder(
          schedule: const ReminderSchedule(),
          today: friday,
          now: morning,
        ),
        isA<RemindersOff>(),
      );
    });

    test('on, but with every weekday deselected', () {
      // Distinct from off: the switch is on and nothing fires, which looks
      // broken unless the screen can say which of the two it is.
      expect(
        nextReminder(
          schedule: onWeekdays(const {}),
          today: friday,
          now: morning,
        ),
        isA<NoDaysChosen>(),
      );
    });

    test('a weekday set that is entirely nonsense', () {
      // Not a loop that never ends. A stored 0 or 9 is a day that never
      // arrives, so a search for the next matching one would run forever.
      expect(
        nextReminder(
          schedule: onWeekdays(const {0, 9, 42}),
          today: friday,
          now: morning,
        ),
        isA<NoDaysChosen>(),
      );
    });

    test('nonsense alongside a real day keeps the real day', () {
      final result = nextReminder(
        schedule: onWeekdays(const {9, 5}),
        today: friday,
        now: morning,
      );
      expect(result, ReminderDue(date: friday, time: eightPm));
    });
  });

  group('today, or the next day after it', () {
    test('later today, when the time has not passed', () {
      expect(
        nextReminder(schedule: daily(), today: friday, now: morning),
        ReminderDue(date: friday, time: eightPm),
      );
    });

    test('tomorrow, once today has gone by', () {
      expect(
        nextReminder(
          schedule: daily(),
          today: friday,
          now: const ReminderTime(21, 0),
        ),
        ReminderDue(date: friday.addDays(1), time: eightPm),
      );
    });

    test('exactly at the reminder time still counts as today', () {
      // A reminder due this minute has not been missed. Sliding it to tomorrow
      // would drop one every time the app is opened on the hour.
      expect(
        nextReminder(schedule: daily(), today: friday, now: eightPm),
        ReminderDue(date: friday, time: eightPm),
      );
    });

    test('one minute past is tomorrow', () {
      expect(
        nextReminder(
          schedule: daily(),
          today: friday,
          now: const ReminderTime(20, 1),
        ),
        ReminderDue(date: friday.addDays(1), time: eightPm),
      );
    });

    test('midnight and 23:59 as the chosen time', () {
      expect(
        nextReminder(
          schedule: daily(time: const ReminderTime(0, 0)),
          today: friday,
          now: const ReminderTime(0, 0),
        ),
        ReminderDue(date: friday, time: const ReminderTime(0, 0)),
      );
      expect(
        nextReminder(
          schedule: daily(time: const ReminderTime(23, 59)),
          today: friday,
          now: const ReminderTime(23, 59),
        ),
        ReminderDue(date: friday, time: const ReminderTime(23, 59)),
      );
    });
  });

  group('a weekly reminder', () {
    test('finds the day later this week', () {
      // Friday is 5; Sunday is 7.
      expect(
        nextReminder(
          schedule: onWeekdays(const {7}),
          today: friday,
          now: morning,
        ),
        ReminderDue(date: friday.addDays(2), time: eightPm),
      );
    });

    test('wraps to next week when the day has gone', () {
      // Monday is 1, and Friday is past it, so the answer is three days on.
      final result = nextReminder(
        schedule: onWeekdays(const {1}),
        today: friday,
        now: morning,
      );
      expect(result, ReminderDue(date: friday.addDays(3), time: eightPm));
      expect((result as ReminderDue).date.weekday, 1);
    });

    test('wraps a full week when today is the day and the time has gone', () {
      final result = nextReminder(
        schedule: onWeekdays(const {5}),
        today: friday,
        now: const ReminderTime(21, 0),
      );
      expect(result, ReminderDue(date: friday.addDays(7), time: eightPm));
      expect((result as ReminderDue).date.weekday, 5);
    });

    test('every weekday of the week is reachable', () {
      // The horizon has to cover a whole week from any starting day. A bound
      // one day short would silently lose whichever day sits furthest away.
      for (var weekday = 1; weekday <= 7; weekday++) {
        final result = nextReminder(
          schedule: onWeekdays({weekday}),
          today: friday,
          now: morning,
        );
        expect(result, isA<ReminderDue>(), reason: 'weekday $weekday');
        expect((result as ReminderDue).date.weekday, weekday);
      }
    });
  });

  group('calendar boundaries', () {
    test('crosses the end of a month', () {
      final endOfApril = aDate(2024, 4, 30);
      expect(
        nextReminder(
          schedule: daily(),
          today: endOfApril,
          now: const ReminderTime(21, 0),
        ),
        ReminderDue(date: aDate(2024, 5, 1), time: eightPm),
      );
    });

    test('crosses the end of a year', () {
      expect(
        nextReminder(
          schedule: daily(),
          today: aDate(2024, 12, 31),
          now: const ReminderTime(21, 0),
        ),
        ReminderDue(date: aDate(2025, 1, 1), time: eightPm),
      );
    });

    test('crosses a leap day rather than skipping it', () {
      expect(
        nextReminder(
          schedule: daily(),
          today: aDate(2024, 2, 28),
          now: const ReminderTime(21, 0),
        ),
        ReminderDue(date: aDate(2024, 2, 29), time: eightPm),
      );
    });

    test(
      'a weekly reminder crossing a month end lands on the right weekday',
      () {
        final result = nextReminder(
          schedule: onWeekdays(const {3}),
          today: aDate(2024, 4, 29),
          now: morning,
        );
        expect(result, isA<ReminderDue>());
        expect((result as ReminderDue).date, aDate(2024, 5, 1));
        expect(result.date.weekday, 3);
      },
    );
  });

  group('skipping a day already logged', () {
    test('a day with nothing logged is worth a reminder', () {
      expect(
        shouldRemindOn(schedule: daily(), date: friday, loggedDays: const {}),
        isTrue,
      );
    });

    test('a day already logged is not', () {
      expect(
        shouldRemindOn(schedule: daily(), date: friday, loggedDays: {friday}),
        isFalse,
      );
    });

    test('another day being logged does not suppress this one', () {
      expect(
        shouldRemindOn(
          schedule: daily(),
          date: friday,
          loggedDays: {friday.subtractDays(1), friday.addDays(1)},
        ),
        isTrue,
      );
    });

    test('a day she did not choose is never reminded on', () {
      // Friday is 5, and this schedule is Mondays only.
      expect(
        shouldRemindOn(
          schedule: onWeekdays(const {1}),
          date: friday,
          loggedDays: const {},
        ),
        isFalse,
      );
    });

    test('nothing is reminded while reminders are off', () {
      expect(
        shouldRemindOn(
          schedule: const ReminderSchedule(),
          date: friday,
          loggedDays: const {},
        ),
        isFalse,
      );
    });

    test('scheduling ignores what is logged, so one stays scheduled', () {
      // The two halves are deliberately separate. If nextReminder skipped
      // logged days, a user who logs every day would eventually have nothing
      // scheduled at all and would never be reminded again.
      expect(
        nextReminder(schedule: daily(), today: friday, now: morning),
        ReminderDue(date: friday, time: eightPm),
      );
      expect(
        shouldRemindOn(schedule: daily(), date: friday, loggedDays: {friday}),
        isFalse,
      );
    });
  });

  group('the schedule model', () {
    test('drops weekdays outside 1..7', () {
      expect(const ReminderSchedule(weekdays: {0, 1, 8, 7}).validWeekdays, {
        1,
        7,
      });
    });

    test('defaults to every day, so turning it on gives a daily reminder', () {
      expect(const ReminderSchedule().validWeekdays, {1, 2, 3, 4, 5, 6, 7});
    });

    test('is off by default', () {
      expect(const ReminderSchedule().enabled, isFalse);
    });
  });
}
