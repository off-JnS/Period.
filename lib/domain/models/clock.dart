import 'cycle_date.dart';

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
}
