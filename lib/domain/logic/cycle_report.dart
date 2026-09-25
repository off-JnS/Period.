import '../models/cycle.dart';
import '../models/cycle_date.dart';
import '../models/cycle_mode.dart';
import '../models/day_entry.dart';
import '../models/symptom.dart';
import 'cycle_analysis.dart';
import 'cycle_statistics.dart';
import 'period_length.dart';

/// How far back a report reaches, in days: a year.
const reportDays = 365;

/// One cycle in the report's table.
class ReportCycle {
  /// Creates the row.
  const ReportCycle({required this.start, this.cycleLength, this.period});

  /// The day the period started.
  final CycleDate start;

  /// The cycle's length in days, or null while in progress.
  final int? cycleLength;

  /// How long the period lasted, as far as the logged flow says.
  final PeriodLength? period;
}

/// How often one thing was logged in the report's range.
class ReportCount {
  /// Creates the count.
  const ReportCount(this.key, this.days);

  /// The logged key, e.g. `cramps` or `mood.sad`.
  final String key;

  /// On how many days it was logged.
  final int days;
}

/// Everything a report for a doctor states, computed from what was logged.
///
/// Description only (CLAUDE.md §8): what was recorded and how often, never
/// what it might mean. Notes, sex and discharge are left out: they are the
/// most private things in the app and a visit does not need them.
class CycleReport {
  /// Creates the report.
  const CycleReport({
    required this.from,
    required this.to,
    required this.mode,
    required this.cycles,
    required this.symptoms,
    required this.moods,
    this.usualCycleLength,
    this.shortestCycle,
    this.longestCycle,
    this.usualPeriodLength,
  });

  /// First day covered.
  final CycleDate from;

  /// Last day covered: the day the report was made.
  final CycleDate to;

  /// The mode she is in, so a reader knows why figures may be missing.
  final CycleMode mode;

  /// Every cycle starting in the range, newest first.
  final List<ReportCycle> cycles;

  /// The median length of the completed cycles; null in pregnancy (§6) or
  /// with too few.
  final int? usualCycleLength;

  /// The shortest completed cycle, with the same conditions.
  final int? shortestCycle;

  /// The longest completed cycle, with the same conditions.
  final int? longestCycle;

  /// The usual period length; shown in every mode (§6).
  final int? usualPeriodLength;

  /// Physical symptoms, most often logged first.
  final List<ReportCount> symptoms;

  /// Moods, most often logged first.
  final List<ReportCount> moods;
}

/// Builds the report covering the [reportDays] days up to [today].
CycleReport buildCycleReport({
  required List<CycleDate> periodStarts,
  required List<DayEntry> entries,
  required CycleSettings settings,
  required CycleDate today,
}) {
  final from = today.subtractDays(reportDays);
  bool inRange(CycleDate day) => !day.isBefore(from) && !day.isAfter(today);

  final allCycles = cyclesFrom(periodStarts);
  final flowByDay = {for (final entry in entries) entry.date: ?entry.flow};
  final starts = [for (final cycle in allCycles) cycle.start];
  final lengths = periodLengths(
    starts: starts,
    flowByDay: flowByDay,
    today: today,
  );
  final periodByStart = {
    for (final (i, start) in starts.indexed) start: lengths[i],
  };

  final inReport = [
    for (final cycle in allCycles)
      if (inRange(cycle.start)) cycle,
  ];
  final eligible = eligibleForStatistics(inReport);
  final showCycleStatistics = settings.cycleStatisticsVisible;
  final sortedLengths = [
    for (final Cycle cycle in eligible) ?cycle.lengthInDays,
  ]..sort();

  final counts = <String, int>{};
  for (final entry in entries) {
    if (!inRange(entry.date)) continue;
    for (final symptom in entry.symptoms) {
      counts[symptom.key] = (counts[symptom.key] ?? 0) + 1;
    }
  }
  List<ReportCount> countsOf(bool Function(String key) include) {
    final list = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (include(key)) ReportCount(key, value),
    ];
    // Most often first; ties in the order the app offers them, so the same
    // data always reads the same.
    final order = [...offeredSymptomKeys, ...offeredMoodKeys];
    list.sort((a, b) {
      final byDays = b.days.compareTo(a.days);
      if (byDays != 0) return byDays;
      return order.indexOf(a.key).compareTo(order.indexOf(b.key));
    });
    return list;
  }

  return CycleReport(
    from: from,
    to: today,
    mode: settings.mode,
    cycles: [
      for (final cycle in inReport.reversed)
        ReportCycle(
          start: cycle.start,
          cycleLength: cycle.lengthInDays,
          period: periodByStart[cycle.start],
        ),
    ],
    usualCycleLength: showCycleStatistics
        ? medianCycleLength(eligible)?.round()
        : null,
    shortestCycle: showCycleStatistics && sortedLengths.isNotEmpty
        ? sortedLengths.first
        : null,
    longestCycle: showCycleStatistics && sortedLengths.isNotEmpty
        ? sortedLengths.last
        : null,
    usualPeriodLength: usualPeriodLength([
      for (final cycle in inReport) ?periodByStart[cycle.start],
    ])?.round(),
    symptoms: countsOf(offeredSymptomKeys.contains),
    moods: countsOf(offeredMoodKeys.contains),
  );
}
