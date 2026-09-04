import '../models/cycle.dart';
import '../models/cycle_date.dart';

/// Turns the stored period start dates into cycles.
///
/// Everything in this file is computed on read, per CLAUDE.md section 4. None of
/// it is ever stored: users retroactively correct start dates constantly, and a
/// persisted cycle would be wrong from the moment they did.

/// Shortest cycle length treated as real, in days.
///
/// Below this is almost certainly a double-logged start, or a start marked
/// partway through a period. See docs/cycle-logic.md section 2.
const shortestPlausibleCycle = 10;

/// Longest cycle length treated as real, in days.
///
/// Above this is almost certainly a missed period start silently merging two
/// cycles into one.
const longestPlausibleCycle = 90;

/// How many recent cycles feed the statistics.
const statisticsWindow = 6;

/// Builds the cycles implied by [periodStarts], oldest first.
///
/// Input may be unsorted and may contain duplicates; both are tolerated, because
/// entries get logged out of order and a day can be marked twice. The most
/// recent cycle has no end and is in progress.
List<Cycle> cyclesFrom(Iterable<CycleDate> periodStarts) {
  final starts = periodStarts.toSet().toList()..sort();
  if (starts.isEmpty) return const [];

  return [
    for (var i = 0; i < starts.length; i++)
      Cycle(
        start: starts[i],
        // A cycle ends the day before the next one begins. The last has not
        // ended yet.
        end: i + 1 < starts.length ? starts[i + 1].subtractDays(1) : null,
      ),
  ];
}

/// The cycles that may be used for statistics: the most recent
/// [statisticsWindow] completed cycles whose length is plausible.
///
/// Implausible lengths are excluded as **logging artifacts, not as unusual
/// bodies**. The thresholds sit far outside any human range precisely so that
/// they catch data errors and nothing else — a genuine 40-day cycle belongs to a
/// real person, and dropping it would make her app quietly wrong about her.
List<Cycle> eligibleForStatistics(Iterable<Cycle> cycles) {
  final completed = [
    for (final cycle in cycles)
      if (_isPlausible(cycle)) cycle,
  ];
  if (completed.length <= statisticsWindow) return completed;
  return completed.sublist(completed.length - statisticsWindow);
}

bool _isPlausible(Cycle cycle) {
  final length = cycle.lengthInDays;
  if (length == null) return false;
  return length >= shortestPlausibleCycle && length <= longestPlausibleCycle;
}

/// Which day of the current cycle [today] is, counting the period start as day
/// 1, or null when there is no cycle in progress on that date.
///
/// Computed on read like everything else here. Returns null when nothing has
/// been logged, and when [today] falls before the first recorded start -- a user
/// looking at a date earlier than her history is not on cycle day zero, she is
/// outside the data.
int? cycleDayOn(CycleDate today, Iterable<CycleDate> periodStarts) {
  final starts = periodStarts.toSet().toList()..sort();
  if (starts.isEmpty) return null;
  if (today.isBefore(starts.first)) return null;

  final start = starts.lastWhere((s) => !s.isAfter(today));
  return start.daysUntil(today) + 1;
}
