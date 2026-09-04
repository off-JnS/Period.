import '../models/cycle.dart';

/// Descriptive statistics over completed cycles.
///
/// Median rather than mean throughout: one anomalous cycle — illness, stress,
/// travel, a forgotten log — should not drag the estimate, and the mean lets it.
/// See docs/cycle-logic.md section 2.

/// The median length of [cycles], or null if none are usable.
///
/// Returns a double because the median of an even number of cycles falls
/// between two of them, and rounding here rather than at the point of use would
/// throw away half a day for no reason.
double? medianCycleLength(Iterable<Cycle> cycles) {
  final lengths = _sortedLengths(cycles);
  if (lengths.isEmpty) return null;
  return _percentile(lengths, 0.5);
}

/// The interquartile spread of the lengths of [cycles], in days.
///
/// The measure of how variable this particular user is, which is what decides
/// how wide her prediction window should be. Interquartile rather than
/// min-to-max so that a single outlying cycle widens the window a little rather
/// than doubling it.
///
/// With only two or three cycles this is necessarily crude; that is what the
/// floor and cap on the prediction window are for.
double? cycleLengthSpread(Iterable<Cycle> cycles) {
  final lengths = _sortedLengths(cycles);
  if (lengths.isEmpty) return null;
  return _percentile(lengths, 0.75) - _percentile(lengths, 0.25);
}

/// The difference between the longest and shortest of [cycles], in days.
///
/// Used by the irregularity hint rather than by prediction, because there the
/// question is whether anything unusual happened at all, not how wide a typical
/// cycle is.
int? cycleLengthRange(Iterable<Cycle> cycles) {
  final lengths = _sortedLengths(cycles);
  if (lengths.isEmpty) return null;
  return (lengths.last - lengths.first).round();
}

List<double> _sortedLengths(Iterable<Cycle> cycles) => [
  for (final cycle in cycles)
    if (cycle.lengthInDays case final length?) length.toDouble(),
]..sort();

/// Linear-interpolation percentile, the same definition most statistics
/// packages use, so a number computed here matches one computed elsewhere.
double _percentile(List<double> sorted, double fraction) {
  if (sorted.length == 1) return sorted.first;
  final position = fraction * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}
