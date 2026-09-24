import 'package:flutter/material.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../log/log_entry_screen.dart';
import 'calendar_screen.dart';
import 'month_grid.dart';

/// Loads a month and hands it to [CalendarScreen].
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
  late int _year;
  late int _month;
  CalendarViewData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final today = widget.clock.today();
    _year = today.year;
    _month = today.month;
    _load();
  }

  Future<void> _load() async {
    try {
      final today = widget.clock.today();
      final starts = await widget.logDao.allPeriodStarts();
      final settings = await widget.settingsDao.cycleSettings();

      // Only the days on screen are read, including the neighbouring-month days
      // the grid shows, so a long history does not make opening a month slower.
      final grid = monthGrid(
        year: _year,
        month: _month,
        // Any week start covers at least the month itself; the exact locale
        // offset only matters for layout, which the screen does.
        firstDayOfWeekIndex: 1,
      );
      final entries = await widget.logDao.entriesBetween(
        grid.days.first.subtractDays(7),
        grid.days.last.addDays(7),
      );

      if (!mounted) return;
      setState(() {
        _error = null;
        _data = CalendarViewData(
          year: _year,
          month: _month,
          today: today,
          periodStarts: starts.toSet(),
          loggedDays: {for (final entry in entries) entry.date},
          predicted: predictedWindowOrNull(
            predictNextPeriod(periodStarts: starts, settings: settings),
          ),
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _step(int months) {
    final total = (_year * 12 + _month - 1) + months;
    setState(() {
      _year = total ~/ 12;
      _month = total % 12 + 1;
    });
    _load();
  }

  Future<void> _openDay(CycleDate date) async {
    final today = widget.clock.today();
    final entry = await widget.logDao.entryOn(date);
    final starts = await widget.logDao.allPeriodStarts();
    if (!mounted) return;

    final result = await showLogEntrySheet(
      context,
      LogEntryScreen(
        date: date,
        today: today,
        entry: entry,
        isPeriodStart: starts.contains(date),
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

    return CalendarScreen(
      data: data,
      onPreviousMonth: () => _step(-1),
      onNextMonth: () => _step(1),
      onSelectDay: _openDay,
    );
  }
}
