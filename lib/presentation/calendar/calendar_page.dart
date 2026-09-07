import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../data_error.dart';
import '../log_day.dart';
import '../providers.dart';
import 'calendar_screen.dart';
import 'month_grid.dart';

/// The calendar connected to the database.
///
/// Kept separate from [CalendarScreen], which stays a pure function of its input
/// so every state can be rendered in a golden file without a database. This is
/// the thin layer that reads real data and writes it back.
class CalendarPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  /// The month on screen, or null while it still follows today.
  ///
  /// Widget state rather than a provider: which month someone is looking at
  /// belongs to this screen and to this visit, and nothing else in the app has
  /// any business reading it.
  CycleDate? _month;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider).today();
    final firstWeekday = firstWeekdayOf(context);
    final grid = MonthGrid.of(
      _month ?? CycleDate(today.year, today.month, 1),
      firstWeekday: firstWeekday,
    );

    final starts = ref.watch(periodStartsProvider);
    final settings = ref.watch(settingsProvider);
    // Only the visible weeks, padding days included, so paging back through
    // years never grows the query.
    final logged = ref.watch(
      loggedDaysProvider((grid.days.first, grid.days.last)),
    );

    if (starts.hasError || logged.hasError || settings.hasError) {
      return _Frame(child: DataErrorPanel(onRetry: _reload));
    }
    // Riverpod keeps the previous value while a re-read is in flight, so a save
    // refreshes the grid in place instead of blanking the month the user is
    // looking at. The spinner is only for the first read.
    if (!starts.hasValue || !logged.hasValue || !settings.hasValue) {
      return const _Frame(child: Center(child: CircularProgressIndicator()));
    }

    // Computed here and stored nowhere, per section 4. A start date corrected
    // on this screen changes the estimate drawn on this screen on the very next
    // build, with no cache to keep in step.
    final periodStarts = starts.requireValue;
    final prediction = predictNextPeriod(
      periodStarts: periodStarts,
      settings: settings.requireValue.cycle,
    );

    return CalendarScreen(
      data: CalendarViewData(
        today: today,
        periodStarts: periodStarts.toSet(),
        loggedDays: logged.requireValue,
        prediction: predictedWindowOrNull(prediction),
      ),
      grid: grid,
      onSelectDay: (day) => logDay(context, ref, day),
      onPreviousMonth: () => setState(() => _month = grid.previous().month),
      onNextMonth: () => setState(() => _month = grid.next().month),
    );
  }

  void _reload() {
    ref
      ..invalidate(periodStartsProvider)
      ..invalidate(settingsProvider)
      ..invalidate(loggedDaysProvider);
  }
}

/// The scaffold [CalendarScreen] builds for itself, for the states before it.
///
/// Loading and failure keep the same title bar as success, so the screen does
/// not appear to change identity while it reads.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).calendarTitle)),
    body: child,
  );
}
