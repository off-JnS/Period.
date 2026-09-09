import '../models/cycle_date.dart';
import '../models/reminder_schedule.dart';
import '../models/reminder_time.dart';

/// When the next log reminder is due, and whether it is still worth showing.
///
/// See docs/cycle-logic.md section 7. Nothing here reads a cycle, a prediction
/// or a mode: a reminder is what the user asked for and nothing more, which is
/// why it behaves identically in every mode including the ones where section 6
/// turns estimates off.
///
/// Pure Dart, no Flutter, per CLAUDE.md section 2.
///
/// The work is deliberately split in two, because a local notification is
/// scheduled well before it appears and nothing of ours runs at the moment it
/// does:
///
/// - [nextReminder] answers *when*, from the schedule alone. It never consults
///   what she has logged, so a reminder is always scheduled and cannot be left
///   permanently unscheduled by a day that happened to be filled in.
/// - [shouldRemindOn] answers *whether it is still wanted*, which is the
///   skip-if-already-logged rule. The platform layer applies it when she logs
///   something, by cancelling a pending reminder that is no longer needed.
///
/// Folding the two together would mean either a reminder that stops being
/// rescheduled or one that cannot be suppressed.

/// How far ahead [nextReminder] will look, in days.
///
/// Today plus a full week, which is enough to find the next match for any
/// schedule down to a single weekday. A bound rather than a loop that runs
/// until it finds something: an empty or nonsensical weekday set would
/// otherwise never terminate.
const _searchHorizonDays = 7;

/// Why there is no reminder, or when the next one is.
///
/// A sealed type rather than a nullable date, for the reason
/// `period_prediction.dart` uses one: every reason for having nothing is
/// explicit, and a caller is forced to say which rather than showing an empty
/// space that reads as a bug.
sealed class NextReminderResult {
  const NextReminderResult();
}

/// She has not turned reminders on.
class RemindersOff extends NextReminderResult {
  /// Creates the result.
  const RemindersOff();
}

/// Reminders are on, but no weekday is selected.
///
/// Distinct from [RemindersOff] because the fix is different and the user is
/// the only one who can make it: a switch that is on and never fires looks
/// broken unless the screen says why.
class NoDaysChosen extends NextReminderResult {
  /// Creates the result.
  const NoDaysChosen();
}

/// The next reminder, as a calendar day and a wall-clock time.
///
/// Deliberately not an instant. docs/cycle-logic.md section 7: resolving this
/// to a point in time is the platform layer's job, done fresh against the
/// timezone in force at that moment, so a clock change moves the reminder with
/// the wall clock instead of dragging it an hour off.
class ReminderDue extends NextReminderResult {
  /// Creates the result.
  const ReminderDue({required this.date, required this.time});

  /// The calendar day it falls on.
  final CycleDate date;

  /// The wall-clock time on that day.
  final ReminderTime time;

  @override
  bool operator ==(Object other) =>
      other is ReminderDue && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => 'ReminderDue(${date.toIso8601()} ${time.toHhMm()})';
}

/// When the next reminder falls, given [schedule].
///
/// [today] and [now] are passed rather than read from a clock, per CLAUDE.md
/// section 3 — the logic is testable by handing it a fixed day and time.
///
/// Today counts only if its time has not already passed. At exactly the
/// reminder time the answer is today: a reminder due this minute has not been
/// missed.
NextReminderResult nextReminder({
  required ReminderSchedule schedule,
  required CycleDate today,
  required ReminderTime now,
}) {
  if (!schedule.enabled) return const RemindersOff();
  if (schedule.validWeekdays.isEmpty) return const NoDaysChosen();

  for (var offset = 0; offset <= _searchHorizonDays; offset++) {
    final day = today.addDays(offset);
    if (!schedule.fallsOnWeekday(day.weekday)) continue;
    // Today is only still ahead of us if the time has not gone by. Every later
    // day is whole, so no time comparison applies to it.
    if (offset == 0 && schedule.time.isBefore(now)) continue;
    return ReminderDue(date: day, time: schedule.time);
  }

  // Unreachable: a non-empty set of weekdays 1..7 always matches within eight
  // consecutive days. Spelled out rather than left to fall off the end, so that
  // if the horizon or the weekday range ever changes this fails loudly instead
  // of returning something plausible.
  throw StateError(
    'No reminder day found within $_searchHorizonDays days for weekdays '
    '${schedule.validWeekdays}',
  );
}

/// Whether a reminder due on [date] is still worth showing.
///
/// False once that day has something logged on it. docs/cycle-logic.md section
/// 7: a reminder to do a thing already done is noise, and an app that generates
/// noise gets its notifications turned off entirely — taking the useful ones
/// with it.
///
/// Takes the logged days as a set rather than reading a database, so this stays
/// pure and a test can state the situation directly.
bool shouldRemindOn({
  required ReminderSchedule schedule,
  required CycleDate date,
  required Set<CycleDate> loggedDays,
}) {
  if (!schedule.enabled) return false;
  if (!schedule.fallsOnWeekday(date.weekday)) return false;
  return !loggedDays.contains(date);
}
