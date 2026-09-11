import 'package:period/domain/models/clock.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/reminder_time.dart';

/// A [Clock] frozen at one calendar day.
///
/// Tests pass a fixed date rather than mocking time, as CLAUDE.md section 3
/// intends. [today] is settable so a test can walk the clock forward without
/// rebuilding whatever depends on it.
class FixedClock implements Clock {
  /// The day this clock reports.
  CycleDate date;

  /// The time of day this clock reports.
  ///
  /// Defaults to the middle of the morning, which is before any plausible
  /// reminder time -- so a test that does not care about the hour gets the
  /// "still to come today" answer rather than an arbitrary one.
  ReminderTime time;

  /// Creates a clock frozen at [date], and at [time] if one is given.
  FixedClock(this.date, {this.time = const ReminderTime(9, 0)});

  @override
  CycleDate today() => date;

  @override
  ReminderTime timeOfDay() => time;
}
