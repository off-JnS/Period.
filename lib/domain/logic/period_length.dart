import '../models/cycle_date.dart';
import '../models/day_entry.dart';
import 'period_prediction.dart';

/// How long one period lasted, as far as what was logged can say.
/// docs/cycle-logic.md §1.
sealed class PeriodLength {
  const PeriodLength();
}

/// A finished run of flow days.
class KnownPeriodLength extends PeriodLength {
  /// Creates the result.
  const KnownPeriodLength(this.days);

  /// Days with flow, counting the start day.
  final int days;

  @override
  bool operator ==(Object other) =>
      other is KnownPeriodLength && other.days == days;

  @override
  int get hashCode => days.hashCode;

  @override
  String toString() => 'KnownPeriodLength($days)';
}

/// A run that reaches today, so the period may not be over.
class OngoingPeriodLength extends PeriodLength {
  /// Creates the result.
  const OngoingPeriodLength(this.daysSoFar);

  /// Days with flow so far, counting the start day and today.
  final int daysSoFar;

  @override
  bool operator ==(Object other) =>
      other is OngoingPeriodLength && other.daysSoFar == daysSoFar;

  @override
  int get hashCode => daysSoFar.hashCode;

  @override
  String toString() => 'OngoingPeriodLength($daysSoFar)';
}

/// No flow was logged on the start day, so there is nothing to count. Not
/// zero: zero would be a figure she never gave.
class UnknownPeriodLength extends PeriodLength {
  /// Creates the result.
  const UnknownPeriodLength();

  @override
  bool operator ==(Object other) => other is UnknownPeriodLength;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'UnknownPeriodLength()';
}

/// How many finished lengths are needed before a usual one is stated. The
/// same bar as for cycles, so the two never disagree about "enough".
const periodsNeededForUsualLength = cyclesNeededToPredict;

/// The duration of the period starting on [start].
///
/// Counts consecutive days from [start] whose flow in [flowByDay] is light,
/// medium or heavy. A day recorded as none, or with no flow recorded, ends the
/// run; so does [nextStart]. A run that reaches [today] is ongoing.
PeriodLength periodLength({
  required CycleDate start,
  required Map<CycleDate, FlowIntensity> flowByDay,
  required CycleDate today,
  CycleDate? nextStart,
}) {
  var days = 0;
  for (var day = start; ; day = day.addDays(1)) {
    if (nextStart != null && !day.isBefore(nextStart)) {
      return days == 0 ? const UnknownPeriodLength() : KnownPeriodLength(days);
    }
    if (day.isAfter(today)) return OngoingPeriodLength(days);

    final flow = flowByDay[day];
    if (flow == null || flow == FlowIntensity.none) {
      return days == 0 ? const UnknownPeriodLength() : KnownPeriodLength(days);
    }
    days++;
  }
}

/// The duration of every period in [starts], in the same order.
///
/// [starts] may arrive in any order; each period is bounded by the next start
/// in date order.
List<PeriodLength> periodLengths({
  required List<CycleDate> starts,
  required Map<CycleDate, FlowIntensity> flowByDay,
  required CycleDate today,
}) {
  final sorted = [...starts]..sort((a, b) => a.compareTo(b));
  final next = {
    for (var i = 0; i < sorted.length; i++)
      sorted[i]: i + 1 < sorted.length ? sorted[i + 1] : null,
  };
  return [
    for (final start in starts)
      periodLength(
        start: start,
        flowByDay: flowByDay,
        today: today,
        nextStart: next[start],
      ),
  ];
}

/// The median of the finished lengths in [lengths], or null until there
/// are [periodsNeededForUsualLength] of them. Ongoing and unknown periods
/// are left out.
double? usualPeriodLength(Iterable<PeriodLength> lengths) {
  final days = [
    for (final duration in lengths)
      if (duration case KnownPeriodLength(:final days)) days,
  ]..sort();
  if (days.length < periodsNeededForUsualLength) return null;
  final middle = days.length ~/ 2;
  return days.length.isOdd
      ? days[middle].toDouble()
      : (days[middle - 1] + days[middle]) / 2;
}
