import '../models/cycle_date.dart';
import '../models/day_entry.dart';
import '../models/symptom.dart';

/// Descriptive statistics about what the user actually logged.
///
/// Nothing here predicts anything, which is why docs/cycle-logic.md section 6
/// allows all of it in every cycle mode -- including the modes where estimates
/// are off. A pregnant user still gets her period durations; she just does not
/// get a guess about the next one.
///
/// Pure Dart, no Flutter, per section 2.

/// Indexes [entries] by day, for [periodDurationFrom].
///
/// Built once and reused across cycles rather than rescanning the entries for
/// each one.
Map<CycleDate, FlowIntensity?> flowByDay(Iterable<DayEntry> entries) => {
  for (final entry in entries) entry.date: entry.flow,
};

/// How many consecutive days from [start] have bleeding recorded.
///
/// docs/cycle-logic.md section 1 defines this exactly: the run of consecutive
/// days from the period start with flow recorded as light, medium or heavy. A
/// day recorded as [FlowIntensity.none], or a day with no flow recorded at all,
/// ends the run.
///
/// Returns 0 when nothing was recorded on the start day itself. That is not a
/// missing value -- it is the honest answer for a start she marked without
/// logging flow, which is common and not an error.
///
/// FIGO puts a normal duration at 2 to 7 days. This does **not** enforce that,
/// or flag it, or clamp to it. The document is explicit that the app reports
/// what was logged, and a number outside that range is a fact about her, not a
/// mistake to be corrected.
int periodDurationFrom(
  CycleDate start,
  Map<CycleDate, FlowIntensity?> flowByDay,
) {
  var days = 0;
  var day = start;
  while (_isBleeding(flowByDay[day])) {
    days++;
    day = day.addDays(1);
  }
  return days;
}

/// Whether [flow] counts towards a period's duration.
///
/// Spelled out rather than defaulted, so adding a value to [FlowIntensity] is a
/// compile error here and someone has to decide what it means.
bool _isBleeding(FlowIntensity? flow) => switch (flow) {
  FlowIntensity.light || FlowIntensity.medium || FlowIntensity.heavy => true,
  // Logged as a period day with no bleeding. She recorded something, and what
  // she recorded was the absence of flow, which ends the run.
  FlowIntensity.none => false,
  // Nothing recorded at all. Section 5 keeps this meaningfully different from
  // `none`, but for a duration both end the run: an unlogged day is not
  // evidence of bleeding.
  null => false,
};

/// How often one symptom was logged.
class SymptomTally {
  /// Creates a tally.
  const SymptomTally({required this.symptom, required this.days});

  /// The symptom, by key. Translated for display, never shown raw.
  final Symptom symptom;

  /// How many days it appears on.
  final int days;
}

/// Every symptom the user has logged, most frequent first.
///
/// Ties break by key so the order is stable: a list that reshuffles between
/// builds for symptoms logged the same number of times would look like the data
/// changed when it did not.
List<SymptomTally> symptomTallies(Iterable<DayEntry> entries) {
  final counts = <String, int>{};
  for (final entry in entries) {
    for (final symptom in entry.symptoms) {
      counts[symptom.key] = (counts[symptom.key] ?? 0) + 1;
    }
  }

  final tallies =
      [
        for (final entry in counts.entries)
          SymptomTally(
            symptom: Symptom(key: entry.key),
            days: entry.value,
          ),
      ]..sort((a, b) {
        final byCount = b.days.compareTo(a.days);
        return byCount != 0 ? byCount : a.symptom.key.compareTo(b.symptom.key);
      });
  return tallies;
}

/// The middle value of [values], or null when there are none.
///
/// Median rather than mean, for the reason docs/cycle-logic.md gives for cycle
/// lengths: one unusual month -- illness, a missed log -- must not drag the
/// number she reads as typical.
int? medianDays(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  // Rounded rather than truncated, so an even count of 4 and 5 days reads as 5
  // rather than 4. Days are whole things; half a day of bleeding is not a
  // number she has any use for.
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

/// How many days have anything at all recorded on them.
int daysLogged(Iterable<DayEntry> entries) => entries.length;
