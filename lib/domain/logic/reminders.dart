import '../models/cycle_date.dart';
import '../models/profile.dart';
import '../models/reminder_settings.dart';
import 'period_prediction.dart';

/// How many days of daily reminders are scheduled ahead.
///
/// Rescheduled every time the app is opened, so this only has to outlast the
/// longest likely gap between uses. 30 plus the period reminder stays well
/// under the 64 pending notifications iOS allows an app.
const dailyReminderHorizonDays = 30;

/// How far ahead the ring and patch reminders are planned.
const methodReminderHorizonDays = 120;

/// The most reminders scheduled at once, under the 64 iOS allows.
const maxPlannedReminders = 60;

/// Which reminder a notification is. Both read the same on the lock screen
/// (CLAUDE.md §9); the kind exists for scheduling and for tests.
enum ReminderKind {
  /// Before the estimated window.
  periodComing,

  /// The daily prompt to log.
  dailyLog,

  /// Take the pill.
  pill,

  /// Take the ring out, after three weeks.
  ringOut,

  /// Put a new ring in, after the break.
  ringIn,

  /// Change the patch.
  patchChange,

  /// Take the patch off for the break week.
  patchOff,

  /// Put on the first patch of a new pack.
  patchOn,

  /// The next injection is a week away.
  injectionSoon,

  /// The next injection is due.
  injectionDue,

  /// The IUD or implant is due for replacement soon.
  deviceSoon,

  /// The IUD or implant is due for replacement.
  deviceDue,
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

/// The reminders to schedule from [today] on, per docs/cycle-logic.md §8,
/// earliest first.
///
/// Pure and recomputed every time (§4): nothing about a reminder is stored but
/// her settings.
///
/// - The period reminder needs an estimate. With predictions off, too few
///   cycles, or cycles too variable, there is no reminder: it never makes a
///   prediction of its own.
/// - It falls [ReminderSettings.daysBefore] days before the window's first
///   day, clamped to the offered range, and is dropped if that day is past.
/// - A contraception reminder is planned only for the kind of [method] she
///   has in her profile, from the dates she entered.
/// - The daily reminder covers [dailyReminderHorizonDays] days from today, or
///   as many as fit under [maxPlannedReminders] after everything else.
///
/// Today is included; whether today's time has already gone is the
/// scheduler's call, since only it knows the time.
List<PlannedReminder> planReminders({
  required ReminderSettings settings,
  required PeriodPrediction prediction,
  required CycleDate today,
  ContraceptionMethod? method,
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

  planned.addAll(
    planMethodReminders(settings: settings, today: today, method: method),
  );

  if (settings.dailyLog) {
    final room = maxPlannedReminders - planned.length;
    for (var i = 0; i < dailyReminderHorizonDays && i < room; i++) {
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

  planned.sort(_byTime);
  return planned.length > maxPlannedReminders
      ? planned.sublist(0, maxPlannedReminders)
      : planned;
}

int _byTime(PlannedReminder a, PlannedReminder b) {
  final days = a.day.compareTo(b.day);
  if (days != 0) return days;
  return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
}

/// The contraception reminders alone, earliest first: for the pill, ring,
/// patch, injection or device, whichever [method] calls for and she switched
/// on. docs/cycle-logic.md §8.
List<PlannedReminder> planMethodReminders({
  required ReminderSettings settings,
  required CycleDate today,
  required ContraceptionMethod? method,
}) {
  final kind = MethodReminder.of(method);
  if (kind == null || !settings.methodOn(kind)) return const [];
  final planned = <PlannedReminder>[];
  final last = today.addDays(methodReminderHorizonDays);

  void at(CycleDate day, ReminderKind kind, {bool pill = false}) {
    if (day.isBefore(today)) return;
    planned.add(
      PlannedReminder(
        day: day,
        hour: pill ? settings.pillHour : settings.methodHour,
        minute: pill ? settings.pillMinute : settings.methodMinute,
        kind: kind,
      ),
    );
  }

  /// Every day [offset] days into a 28-day round from [start], up to [last].
  void everyRound(CycleDate start, int offset, ReminderKind kind) {
    // The first round that can still reach today.
    var round = start.daysUntil(today) ~/ PillPack.length - 1;
    if (round < 0) round = 0;
    for (; ; round++) {
      final day = start.addDays(round * PillPack.length + offset);
      if (day.isAfter(last)) return;
      at(day, kind);
    }
  }

  switch (kind) {
    case MethodReminder.pill:
      final pack = settings.pillPack;
      final start = settings.pillPackStart;
      for (var i = 0; i < dailyReminderHorizonDays; i++) {
        final day = today.addDays(i);
        // Without a first day, every day: a reminder too many on a break
        // day is safer than one missing on a pill day.
        if (pack.hasBreak && start != null) {
          final inPack = start.daysUntil(day) % PillPack.length;
          if (inPack >= pack.activeDays) continue;
        }
        at(day, ReminderKind.pill, pill: true);
      }
    case MethodReminder.ring:
      if (settings.ringInserted case final start?) {
        everyRound(start, 21, ReminderKind.ringOut);
        everyRound(start, 28, ReminderKind.ringIn);
      }
    case MethodReminder.patch:
      if (settings.patchStarted case final start?) {
        everyRound(start, 7, ReminderKind.patchChange);
        everyRound(start, 14, ReminderKind.patchChange);
        everyRound(start, 21, ReminderKind.patchOff);
        everyRound(start, 28, ReminderKind.patchOn);
      }
    case MethodReminder.injection:
      if (settings.injectionLast case final lastShot?) {
        final weeks = settings.injectionWeeks.clamp(
          ReminderSettings.minInjectionWeeks,
          ReminderSettings.maxInjectionWeeks,
        );
        final due = lastShot.addDays(weeks * 7);
        at(due.subtractDays(7), ReminderKind.injectionSoon);
        at(due, ReminderKind.injectionDue);
      }
    case MethodReminder.device:
      if (settings.deviceReplaceBy case final due?) {
        at(
          due.subtractDays(settings.deviceWeeksBefore * 7),
          ReminderKind.deviceSoon,
        );
        at(due, ReminderKind.deviceDue);
      }
  }

  planned.sort(_byTime);
  return planned;
}
