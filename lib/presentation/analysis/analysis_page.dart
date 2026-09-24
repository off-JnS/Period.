import 'package:flutter/material.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/cycle_statistics.dart';
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
    super.key,
  });

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
      if (!mounted) return;
      setState(() {
        _error = null;
        _data = analysisFrom(
          starts,
          statisticsVisible: settings.cycleStatisticsVisible,
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
AnalysisViewData analysisFrom(
  List<CycleDate> periodStarts, {
  bool statisticsVisible = true,
}) {
  final cycles = cyclesFrom(periodStarts);
  final eligible = eligibleForStatistics(cycles);

  final lengths = [for (final cycle in eligible) ?cycle.lengthInDays]..sort();

  return AnalysisViewData(
    statisticsVisible: statisticsVisible,
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
