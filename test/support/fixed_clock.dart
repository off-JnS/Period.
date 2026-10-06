import 'package:period/domain/models/clock.dart';
import 'package:period/domain/models/cycle_date.dart';

/// A [Clock] frozen at one calendar day.
///
/// Tests pass a fixed date rather than mocking time, as CLAUDE.md section 3
/// intends. [today] is settable so a test can walk the clock forward without
/// rebuilding whatever depends on it.
class FixedClock implements Clock {
  /// The day this clock reports.
  CycleDate date;

  /// Creates a clock frozen at [date].
  FixedClock(this.date);

  @override
  CycleDate today() => date;
}
