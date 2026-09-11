import 'cycle_date.dart';
import 'reminder_time.dart';

/// Supplies today's calendar day.
///
/// CLAUDE.md section 3 allows `DateTime.now()` in exactly one place. This is the
/// abstraction that place implements; everything else takes the date as a
/// parameter, so the logic can be tested by passing a fixed day instead of
/// mocking time.
///
/// The concrete implementation lives outside the domain, in
/// `lib/data/system_clock.dart`, which keeps this layer free of [DateTime]
/// entirely. Tests use `FixedClock` from `test/support/fixed_clock.dart`.
abstract class Clock {
  /// The calendar day it is now, wherever the device currently is.
  CycleDate today();

  /// The time of day it is now, on the wall clock the user is looking at.
  ///
  /// Here rather than read wherever it is wanted, for the same reason [today]
  /// is: it is the other half of the single permitted `DateTime.now()`. Only
  /// the reminder needs it, and only to decide whether today's reminder time
  /// has already gone by -- see `nextReminder`.
  ///
  /// A [ReminderTime], not a [DateTime] and not a Flutter [TimeOfDay]: hours
  /// and minutes with no date, no offset and no zone, so nothing here can carry
  /// a timestamp into the domain.
  ReminderTime timeOfDay();
}
