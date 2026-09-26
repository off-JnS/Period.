import '../models/cycle_date.dart';
import '../models/day_entry.dart';
import 'period_length.dart';

/// A period that began in a given month, with how long it lasted.
class MonthPeriod {
  /// Creates the value.
  const MonthPeriod({required this.start, required this.length});

  /// The day she marked as the start.
  final CycleDate start;

  /// How long it ran, derived from the flow she logged (docs/cycle-logic.md
  /// §1).
  final PeriodLength length;

  /// The last day of the period, when it has finished.
  CycleDate? get lastDay => switch (length) {
    KnownPeriodLength(:final days) => start.addDays(days - 1),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is MonthPeriod && other.start == start && other.length == length;

  @override
  int get hashCode => Object.hash(start, length);

  @override
  String toString() => 'MonthPeriod($start, $length)';
}

/// Every period that started in [month] of [year], oldest first.
///
/// A period belongs to the month it started in, so one that runs from
/// 30 August into September is listed under August only. [starts] may arrive
/// in any order.
List<MonthPeriod> periodsStartingIn({
  required int year,
  required int month,
  required List<CycleDate> starts,
  required Map<CycleDate, FlowIntensity> flowByDay,
  required CycleDate today,
}) {
  final sorted = [...starts]..sort((a, b) => a.compareTo(b));
  return [
    for (final (index, start) in sorted.indexed)
      if (start.year == year && start.month == month)
        MonthPeriod(
          start: start,
          length: periodLength(
            start: start,
            flowByDay: flowByDay,
            today: today,
            nextStart: index + 1 < sorted.length ? sorted[index + 1] : null,
          ),
        ),
  ];
}

/// Whether the calendar draws [date] as a period day: a day she marked as a
/// start, or a day she logged light, medium or heavy flow.
///
/// What she recorded, nothing inferred. Flow logged without a start still
/// shows, because she did log bleeding that day; it just does not begin a
/// cycle (docs/cycle-logic.md §1).
bool isPeriodDay(
  CycleDate date, {
  required Set<CycleDate> starts,
  required Map<CycleDate, FlowIntensity> flowByDay,
}) {
  if (starts.contains(date)) return true;
  final flow = flowByDay[date];
  return flow != null && flow != FlowIntensity.none;
}

/// Whether the range from [earliest] to [latest] touches [month] of [year].
bool rangeTouchesMonth({
  required CycleDate earliest,
  required CycleDate latest,
  required int year,
  required int month,
}) {
  final first = CycleDate(year, month, 1);
  final last = CycleDate(year, month, CycleDate.lastDayOfMonth(year, month));
  return !latest.isBefore(first) && !earliest.isAfter(last);
}
