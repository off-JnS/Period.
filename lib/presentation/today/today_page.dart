import 'package:flutter/material.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/cycle_statistics.dart';
import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/irregularity.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/day_entry.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../log/log_entry_screen.dart';
import 'today_screen.dart';

/// Loads what the user recorded and hands it to [TodayScreen].
///
/// The split is the point: everything below this widget is a pure function of
/// its input, and everything that touches the database is here. Section 4 also
/// lands here — the cycles, the cycle day, the prediction and the fertile window
/// are all recomputed from the stored period starts on every load, and none of
/// them is written back.
class TodayPage extends StatefulWidget {
  /// Creates the page.
  const TodayPage({
    required this.logDao,
    required this.settingsDao,
    required this.clock,
    this.onEntriesChanged,
    super.key,
  });

  /// Told after anything is saved or deleted, since a new period start moves
  /// the estimate and with it the reminder.
  final VoidCallback? onEntriesChanged;

  /// Reads and writes what the user logged.
  final LogDao logDao;

  /// Reads the mode and opt-ins every estimate is computed under.
  final SettingsDao settingsDao;

  /// Supplies today's calendar day.
  final Clock clock;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  TodayViewData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final today = widget.clock.today();
      final starts = await widget.logDao.allPeriodStarts();
      final entry = await widget.logDao.entryOn(today);
      final settings = await widget.settingsDao.cycleSettings();

      if (!mounted) return;
      setState(() {
        _error = null;
        _data = _viewDataFrom(
          today: today,
          periodStarts: starts,
          todayEntry: entry,
          settings: settings,
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// Recomputes everything the screen shows from the stored facts.
  ///
  /// Static and taking only values so it can be exercised without a database.
  static TodayViewData _viewDataFrom({
    required CycleDate today,
    required List<CycleDate> periodStarts,
    required DayEntry? todayEntry,
    required CycleSettings settings,
  }) {
    final cycles = cyclesFrom(periodStarts);
    final eligible = eligibleForStatistics(cycles);
    final prediction = predictNextPeriod(
      periodStarts: periodStarts,
      settings: settings,
    );

    return TodayViewData(
      cycleDay: cycleDayOn(today, periodStarts),
      // The ring fills against the user's own median, never against 28. A
      // fallback here would draw a confident arc from an assumption she never
      // made.
      //
      // Withheld in pregnancy, where docs/cycle-logic.md section 6 hides
      // cycle statistics; the ring then shows the day with a neutral arc.
      typicalCycleLength: settings.cycleStatisticsVisible
          ? medianCycleLength(eligible)?.round()
          : null,
      prediction: prediction,
      fertileWindow: estimateFertileWindow(
        prediction: prediction,
        optedIn: settings.fertileWindowOptedIn,
      ),
      // The hint is read off the same statistics, so it goes with them.
      showDoctorHint:
          settings.cycleStatisticsVisible &&
          shouldSuggestSeeingADoctor(eligible),
      todayEntry: todayEntry,
      isTodayPeriodStart: periodStarts.contains(today),
    );
  }

  Future<void> _openLog({required CycleDate date}) async {
    final today = widget.clock.today();
    final entry = await widget.logDao.entryOn(date);
    final starts = await widget.logDao.allPeriodStarts();
    final settings = await widget.settingsDao.cycleSettings();
    if (!mounted) return;

    final result = await showLogEntrySheet(
      context,
      LogEntryScreen(
        date: date,
        today: today,
        entry: entry,
        isPeriodStart: starts.contains(date),
        offerPill: settings.mode == CycleMode.hormonalContraception,
      ),
    );
    if (result == null || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    switch (result) {
      case LogEntrySaved(:final draft):
        await _save(draft);
        messenger.showSnackBar(SnackBar(content: Text(l10n.entrySaved)));
      case LogEntryDeleted(:final date):
        await _delete(date);
        messenger.showSnackBar(SnackBar(content: Text(l10n.entryDeleted)));
    }

    widget.onEntriesChanged?.call();
    await _load();
  }

  Future<void> _save(LogEntryDraft draft) async {
    await widget.logDao.saveEntry(draft.entry);
    // Marking and unmarking are both written, so that turning the switch off is
    // a correction rather than a no-op. Section 4 makes this cheap: nothing
    // derived is stored, so nothing has to be rebuilt.
    if (draft.isPeriodStart) {
      await widget.logDao.addPeriodStart(draft.entry.date);
    } else {
      await widget.logDao.removePeriodStart(draft.entry.date);
    }
  }

  Future<void> _delete(CycleDate date) async {
    await widget.logDao.deleteEntry(date);
    // The confirmation says the period start goes too, so it goes.
    await widget.logDao.removePeriodStart(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_error != null) {
      return GroupedPage(
        title: l10n.todayTitle,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.couldNotOpenData,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }

    final data = _data;
    if (data == null) {
      // Same title as the loaded screen, so the switch is not a jump.
      return GroupedPage(
        title: l10n.todayTitle,
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator.adaptive()),
        ],
      );
    }

    return TodayScreen(
      data: data,
      onAddEntry: () => _openLog(date: widget.clock.today()),
      onEditToday: () => _openLog(date: widget.clock.today()),
    );
  }
}
