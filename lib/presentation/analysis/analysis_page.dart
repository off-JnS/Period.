import 'package:flutter/material.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/cycle_statistics.dart';
import '../../domain/logic/period_length.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import 'analysis_screen.dart';

/// Loads the cycle history and hands it to [AnalysisScreen].
///
/// Every figure on that screen is computed here, on read, from the stored period
/// starts -- the same `cycleStatistics` functions the prediction uses, so the two
/// screens can never disagree about how long her cycles usually are.
class AnalysisPage extends StatefulWidget {
  /// Creates the page.
  const AnalysisPage({
    required this.logDao,
    required this.settingsDao,
    required this.clock,
    super.key,
  });

  /// Supplies today, which decides whether a period is still running.
  final Clock clock;

  /// Reads what the user logged.
  final LogDao logDao;

  /// Reads the mode, which decides whether statistics are shown.
  final SettingsDao settingsDao;

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  AnalysisViewData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final starts = await widget.logDao.allPeriodStarts();
      final settings = await widget.settingsDao.cycleSettings();
      final today = widget.clock.today();
      // Flow from the first start on: lengths only ever count forward from
      // a start, so nothing earlier can matter.
      final entries = starts.isEmpty
          ? const <DayEntry>[]
          : await widget.logDao.entriesBetween(starts.first, today);
      if (!mounted) return;
      setState(() {
        _error = null;
        _data = analysisFrom(
          starts,
          statisticsVisible: settings.cycleStatisticsVisible,
          flowByDay: {for (final entry in entries) entry.date: ?entry.flow},
          today: today,
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_error != null) {
      return GroupedPage(
        title: l10n.analysisTitle,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.couldNotOpenData, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    final data = _data;
    if (data == null) {
      // Same title as the loaded screen, so the switch is not a jump.
      return GroupedPage(
        title: l10n.analysisTitle,
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator.adaptive()),
        ],
      );
    }

    return AnalysisScreen(data: data);
  }
}

/// Derives the whole screen from the recorded period starts.
///
/// A free function so it can be tested as a function, with no widget and no
/// database: the interesting cases here are all about the shape of the history.
///
/// Period lengths need [today] and the logged [flowByDay]; without [today]
/// none are computed.
AnalysisViewData analysisFrom(
  List<CycleDate> periodStarts, {
  bool statisticsVisible = true,
  Map<CycleDate, FlowIntensity> flowByDay = const {},
  CycleDate? today,
}) {
  final cycles = cyclesFrom(periodStarts);
  final eligible = eligibleForStatistics(cycles);

  final lengths = [for (final cycle in eligible) ?cycle.lengthInDays]..sort();

  final periods = today == null
      ? const <PeriodLength>[]
      : periodLengths(starts: periodStarts, flowByDay: flowByDay, today: today);

  return AnalysisViewData(
    statisticsVisible: statisticsVisible,
    periodLengths: {
      for (final (i, start) in periodStarts.indexed)
        if (i < periods.length) start: periods[i],
    },
    usualPeriodLength: usualPeriodLength(periods)?.round(),
    knownPeriodCount: periods.whereType<KnownPeriodLength>().length,
    cycles: cycles,
    eligible: eligible,
    // Null until there is enough to be worth stating. The screen says so in
    // words rather than showing a figure computed from one cycle.
    medianLength: eligible.length < 2
        ? null
        : medianCycleLength(eligible)?.round(),
    shortest: lengths.isEmpty ? null : lengths.first,
    longest: lengths.isEmpty ? null : lengths.last,
  );
}
