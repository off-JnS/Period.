import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/cycle_report.dart';
import '../../domain/logic/cycle_statistics.dart';
import '../../domain/logic/period_length.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../report/report_pdf.dart';
import '../report/share_report.dart';
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
    this.shareFile = systemShare,
    this.temporaryDirectory = getTemporaryDirectory,
    super.key,
  });

  /// Where the PDF is written before sharing; a parameter for tests.
  final Future<Directory> Function() temporaryDirectory;

  /// Where the finished report goes; the system share sheet unless a test
  /// says otherwise.
  final FileSharer shareFile;

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
  bool _sharing = false;

  /// Builds the report from what is stored now, draws it, and shares it.
  Future<void> _shareReport(Rect? origin) async {
    if (_sharing) return;
    _sharing = true;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final today = widget.clock.today();
      final report = buildCycleReport(
        periodStarts: await widget.logDao.allPeriodStarts(),
        // A little before the range, so a period starting just inside it can
        // still find its flow and its predecessor's length.
        entries: await widget.logDao.entriesBetween(
          today.subtractDays(reportDays + 60),
          today,
        ),
        settings: await widget.settingsDao.cycleSettings(),
        today: today,
      );
      final bytes = await renderReportPdf(report, l10n: l10n, locale: locale);
      await sharePdf(
        bytes,
        fileName: '${l10n.reportFileName}-${today.toIso8601()}',
        share: widget.shareFile,
        origin: origin,
        directory: widget.temporaryDirectory,
      );
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.reportFailed)));
    } finally {
      _sharing = false;
    }
  }

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

    return AnalysisScreen(data: data, onShareReport: _shareReport);
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
