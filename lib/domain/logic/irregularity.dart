import '../models/cycle.dart';
import 'cycle_statistics.dart';

/// Fewest completed cycles before the hint can appear at all.
const cyclesNeededForHint = 3;

/// Cycle length range, in days, beyond which the hint may appear.
///
/// Mirrors STRAW+10, which treats a persistent difference of 7 days or more
/// between consecutive cycles as clinically meaningful, set slightly higher so
/// the hint stays rare.
const notableRangeInDays = 9;

/// Shortest cycle length FIGO considers normal, in days.
const shortestUsualCycle = 24;

/// Longest cycle length FIGO considers normal, in days.
const longestUsualCycle = 38;

/// How many cycles outside the usual range make the hint appear.
const unusualCyclesNeeded = 2;

/// Whether to offer the "might be worth mentioning to a doctor" hint.
///
/// This is **not** a finding, a diagnosis, or a label attached to the user, and
/// the wording that surfaces it must not become one — section 8 is explicit. It
/// is a suggestion that a conversation might be worth having.
///
/// Deliberately hard to trigger. A hint that fires every time someone has a
/// stressful month gets dismissed, or frightens a person whose cycle is
/// perfectly ordinary; it earns attention by being uncommon. See
/// docs/cycle-logic.md section 5.
bool shouldSuggestSeeingADoctor(Iterable<Cycle> eligibleCycles) {
  final cycles = eligibleCycles.toList();
  if (cycles.length < cyclesNeededForHint) return false;

  final range = cycleLengthRange(cycles);
  if (range != null && range > notableRangeInDays) return true;

  final unusual = cycles.where((cycle) {
    final length = cycle.lengthInDays;
    if (length == null) return false;
    return length < shortestUsualCycle || length > longestUsualCycle;
  }).length;

  return unusual >= unusualCyclesNeeded;
}
