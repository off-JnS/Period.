import 'package:flutter/material.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../log/log_entry_screen.dart';
import 'calendar_screen.dart';
import 'day_preview.dart';

/// Loads what the calendar shows and hands it to [CalendarScreen].
///
/// The same split as `TodayPage`: the database stops here. The estimated window
/// is recomputed from the stored period starts on every load rather than being
/// carried over from the Today screen, because section 4 forbids caching it and
/// the user may have corrected a start date in between.
class CalendarPage extends StatefulWidget {
  /// Creates the page.
  const CalendarPage({
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

  /// Reads the mode the estimate is computed under.
  final SettingsDao settingsDao;

  /// Supplies today's calendar day.
  final Clock clock;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarViewData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the whole history at once. The calendar scrolls through all of
  /// it, and two small queries over every logged day cost less than reading
  /// month by month as she scrolls.
  Future<void> _load() async {
    try {
      final today = widget.clock.today();
      final starts = await widget.logDao.allPeriodStarts();
      final settings = await widget.settingsDao.cycleSettings();
      final days = await widget.logDao.loggedDays();
      final prediction = predictNextPeriod(
        periodStarts: starts,
        settings: settings,
      );

      if (!mounted) return;
      setState(() {
        _error = null;
        _data = CalendarViewData(
          today: today,
          periodStarts: starts.toSet(),
          flowByDay: days.flow,
          loggedDays: days.logged,
          predicted: predictedWindowOrNull(prediction),
          fertileWindow: estimateFertileWindow(
            prediction: prediction,
            optedIn: settings.fertileWindowOptedIn,
          ),
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// Shows [date] at a glance, then opens it for editing if she asks.
  Future<void> _previewDay(CycleDate date) async {
    final data = _data;
    if (data == null) return;
    final entry = await widget.logDao.entryOn(date);
    if (!mounted) return;

    final edit = await showDayPreview(
      context,
      DayPreviewData(
        date: date,
        today: data.today,
        entry: entry,
        isPeriodStart: data.periodStarts.contains(date),
        marker: data.markerOn(date),
        // Only for days that have happened: a future cycle day would be a
        // count along an estimate, stated as if it were a fact.
        cycleDay: date.isAfter(data.today)
            ? null
            : cycleDayOn(date, data.periodStarts),
      ),
    );
    if (edit && mounted) await _openDay(date);
  }

  Future<void> _openDay(CycleDate date) async {
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

    switch (result) {
      case LogEntrySaved(:final draft):
        await widget.logDao.saveEntry(draft.entry);
        if (draft.isPeriodStart) {
          await widget.logDao.addPeriodStart(draft.entry.date);
        } else {
          await widget.logDao.removePeriodStart(draft.entry.date);
        }
      case LogEntryDeleted(:final date):
        await widget.logDao.deleteEntry(date);
        await widget.logDao.removePeriodStart(date);
    }

    widget.onEntriesChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_error != null) {
      return GroupedPage(
        title: l10n.calendarTitle,
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
        title: l10n.calendarTitle,
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator.adaptive()),
        ],
      );
    }

    return CalendarScreen(data: data, onSelectDay: _previewDay);
  }
}
