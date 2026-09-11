import 'package:freezed_annotation/freezed_annotation.dart';

import 'reminder_time.dart';

part 'reminder_schedule.freezed.dart';

/// When the user asked to be reminded to log.
///
/// Chosen entirely by her: a time of day, and which weekdays. Nothing here is
/// derived from a prediction, a phase or a cycle length, which is what
/// docs/cycle-logic.md section 7 means by a reminder carrying no inference —
/// and why this type needs no [CycleMode] and no mode gate.
@freezed
abstract class ReminderSchedule with _$ReminderSchedule {
  const ReminderSchedule._();

  const factory ReminderSchedule({
    /// Whether she asked to be reminded at all. Off until she says otherwise.
    @Default(false) bool enabled,

    /// The wall-clock time she chose.
    ///
    /// The default is only what a picker would open on; it means nothing while
    /// [enabled] is false, and it is not a recommendation about when anyone
    /// should log.
    @Default(ReminderTime(20, 0)) ReminderTime time,

    /// The weekdays it fires on, 1 (Monday) through 7 (Sunday), matching
    /// [CycleDate.weekday].
    ///
    /// All seven is a daily reminder and one is a weekly one, so a single type
    /// covers both without a mode flag to keep in step with the set.
    @Default({1, 2, 3, 4, 5, 6, 7}) Set<int> weekdays,
  }) = _ReminderSchedule;

  /// The chosen weekdays that are real weekdays.
  ///
  /// Anything outside 1 through 7 is dropped rather than trusted. A stored set
  /// is only as good as whatever wrote it, and a value like 9 would otherwise
  /// be a day that never arrives — which, in a search for the next matching
  /// day, is a loop that does not end. Dropping it resolves to "no days
  /// chosen", so nothing fires, which is the safe direction for an opt-in.
  Set<int> get validWeekdays =>
      weekdays.where((day) => day >= 1 && day <= 7).toSet();

  /// Whether a reminder is wanted on [weekday], 1 (Monday) through 7 (Sunday).
  bool fallsOnWeekday(int weekday) => validWeekdays.contains(weekday);
}
