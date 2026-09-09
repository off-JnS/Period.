import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/logged_summary.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../l10n/app_localizations.dart';
import '../data_error.dart';
import '../providers.dart';
import 'analysis_screen.dart';

/// The analysis screen connected to the database.
class AnalysisPage extends ConsumerWidget {
  /// Creates the page.
  const AnalysisPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final starts = ref.watch(periodStartsProvider);
    final entries = ref.watch(allEntriesProvider);

    Widget frame(Widget child) => Scaffold(
      appBar: AppBar(title: Text(l10n.analysisTitle)),
      body: child,
    );

    if (starts.hasError || entries.hasError) {
      return frame(DataErrorPanel(onRetry: () => _reload(ref)));
    }
    if (!starts.hasValue || !entries.hasValue) {
      return frame(const Center(child: CircularProgressIndicator()));
    }

    return AnalysisScreen(
      data: summarise(starts.requireValue, entries.requireValue),
    );
  }

  void _reload(WidgetRef ref) {
    ref
      ..invalidate(periodStartsProvider)
      ..invalidate(allEntriesProvider);
  }
}

/// Everything on the screen, computed on read from the stored rows.
///
/// Nothing here is persisted, per section 4: a retroactively corrected start
/// date changes every number the next time this builds, with no cache to keep in
/// step.
///
/// Note what is deliberately *not* consulted: the cycle mode.
/// docs/cycle-logic.md section 6 allows pure description in every mode, and
/// nothing computed here is a prediction.
AnalysisViewData summarise(
  List<CycleDate> periodStarts,
  List<DayEntry> entries,
) {
  final eligible = eligibleForStatistics(cyclesFrom(periodStarts));
  final flow = flowByDay(entries);

  final summaries = [
    for (final cycle in eligible)
      if (cycle.lengthInDays case final length?)
        CycleSummary(
          startedOn: DateTime(
            cycle.start.year,
            cycle.start.month,
            cycle.start.day,
          ),
          lengthInDays: length,
          periodDays: periodDurationFrom(cycle.start, flow),
        ),
  ];

  final lengths = [for (final cycle in summaries) cycle.lengthInDays]..sort();
  // Only durations that were actually recorded. A start she marked without
  // logging any flow is a zero, and averaging those in would report a shorter
  // typical period than she has ever had.
  final durations = [
    for (final cycle in summaries)
      if (cycle.periodDays > 0) cycle.periodDays,
  ];

  return AnalysisViewData(
    cycles: summaries,
    symptoms: symptomTallies(entries),
    daysLogged: daysLogged(entries),
    typicalLength: lengths.length >= 2 ? medianDays(lengths) : null,
    shortestLength: lengths.isEmpty ? null : lengths.first,
    longestLength: lengths.isEmpty ? null : lengths.last,
    typicalPeriodDays: medianDays(durations),
  );
}
