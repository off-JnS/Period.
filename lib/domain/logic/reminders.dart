import '../models/cycle_date.dart';
import '../models/reminder_settings.dart';
import 'period_prediction.dart';

/// How many days of daily reminders are scheduled ahead.
///
/// Rescheduled every time the app is opened, so this only has to outlast the
/// longest likely gap between uses. 30 plus the period reminder stays well
/// under the 64 pending notifications iOS allows an app.
const dailyReminderHorizonDays = 30;

/// Which reminder a notification is. Both read the same on the lock screen
/// (CLAUDE.md §9); the kind exists for scheduling and for tests.
enum ReminderKind {
  /// Before the estimated window.
  periodComing,

  /// The daily prompt to log.
  dailyLog,
}

/// One reminder to schedule: a calendar day and a time on it.
///
/// A day and a clock time rather than an instant, so the domain stays free of
/// timestamps (§3). The scheduler turns it into an instant in the device's
/// local time, and drops any that has already passed.
class PlannedReminder {
  /// Creates the reminder.
  const PlannedReminder({
    required this.day,
    required this.hour,
    required this.minute,
    required this.kind,
  });

  /// The calendar day it arrives on.
  final CycleDate day;

  /// The hour, 0 to 23.
  final int hour;

  /// The minute, 0 to 59.
  final int minute;

  /// Which reminder this is.
  final ReminderKind kind;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(day, hour, minute, kind);

  @override
  String toString() =>
      'PlannedReminder(${day.toIso8601()} $hour:$minute ${kind.name})';
}

/// The reminders to schedule from [today] on, per docs/cycle-logic.md §8.
///
/// Pure and recomputed every time (§4): nothing about a reminder is stored but
/// her settings.
///
/// - The period reminder needs an estimate. With predictions off, too few
///   cycles, or cycles too variable, there is no reminder: it never makes a
///   prediction of its own.
/// - It falls [ReminderSettings.daysBefore] days before the window's first
///   day, clamped to the offered range, and is dropped if that day is past.
/// - The daily reminder covers [dailyReminderHorizonDays] days from today.
///
/// Today is included; whether today's time has already gone is the
/// scheduler's call, since only it knows the time.
List<PlannedReminder> planReminders({
  required ReminderSettings settings,
  required PeriodPrediction prediction,
  required CycleDate today,
}) {
  final planned = <PlannedReminder>[];

  if (settings.periodComing && prediction is PredictedPeriod) {
    final lead = settings.daysBefore.clamp(
      ReminderSettings.minDaysBefore,
      ReminderSettings.maxDaysBefore,
    );
    final day = prediction.earliest.subtractDays(lead);
    if (!day.isBefore(today)) {
      planned.add(
        PlannedReminder(
          day: day,
          hour: settings.hour,
          minute: settings.minute,
          kind: ReminderKind.periodComing,
        ),
      );
    }
  }

  if (settings.dailyLog) {
    for (var i = 0; i < dailyReminderHorizonDays; i++) {
      planned.add(
        PlannedReminder(
          day: today.addDays(i),
          hour: settings.hour,
          minute: settings.minute,
          kind: ReminderKind.dailyLog,
        ),
      );
    }
  }

  return planned;
}
