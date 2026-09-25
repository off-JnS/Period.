import '../models/cycle_date.dart';

/// The last day the counter runs to: 44 weeks and 0 days. docs/cycle-logic.md §6.
const pregnancyCounterLastDay = 44 * 7;

/// How far along a pregnancy is, counted from the first day of the last
/// period: completed [weeks] plus [days], written 12+3.
class PregnancyWeek {
  /// Creates the value.
  const PregnancyWeek({required this.weeks, required this.days});

  /// Completed weeks.
  final int weeks;

  /// Days into the current week, 0 to 6.
  final int days;

  /// Total days since the first day of the last period.
  int get totalDays => weeks * 7 + days;

  @override
  bool operator ==(Object other) =>
      other is PregnancyWeek && other.weeks == weeks && other.days == days;

  @override
  int get hashCode => Object.hash(weeks, days);

  @override
  String toString() => 'PregnancyWeek($weeks+$days)';
}

/// What Today can say about the pregnancy.
sealed class PregnancyCount {
  const PregnancyCount();
}

/// Counting: [week] since the last period.
class PregnancyCounting extends PregnancyCount {
  /// Creates the result.
  const PregnancyCounting(this.week);

  /// How far along.
  final PregnancyWeek week;
}

/// No period start recorded, so there is nothing to count from.
class PregnancyNeedsLastPeriod extends PregnancyCount {
  /// Creates the result.
  const PregnancyNeedsLastPeriod();
}

/// Past 44+0: the counter has stopped and the mode may be out of date.
class PregnancyCounterEnded extends PregnancyCount {
  /// Creates the result.
  const PregnancyCounterEnded();
}

/// Counts the pregnancy on [today] from the latest of [periodStarts] on or
/// before it. See docs/cycle-logic.md §6.
PregnancyCount pregnancyCountOn(
  CycleDate today,
  Iterable<CycleDate> periodStarts,
) {
  CycleDate? last;
  for (final start in periodStarts) {
    if (start.isAfter(today)) continue;
    if (last == null || start.isAfter(last)) last = start;
  }
  if (last == null) return const PregnancyNeedsLastPeriod();

  final elapsed = last.daysUntil(today);
  if (elapsed > pregnancyCounterLastDay) return const PregnancyCounterEnded();
  return PregnancyCounting(
    PregnancyWeek(weeks: elapsed ~/ 7, days: elapsed % 7),
  );
}
