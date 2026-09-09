import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import 'month_grid.dart';

/// Everything the calendar needs for one month, already computed.
///
/// Like the Today screen, the widget is a pure function of this so every state
/// can be rendered in a golden file without a database.
class CalendarViewData {
  /// Creates the view data.
  const CalendarViewData({
    required this.today,
    this.periodStarts = const {},
    this.loggedDays = const {},
    this.prediction,
  });

  /// The current day, marked distinctly.
  final CycleDate today;

  /// Days the user marked as a period start.
  final Set<CycleDate> periodStarts;

  /// Days with any entry at all.
  final Set<CycleDate> loggedDays;

  /// The estimated next period, when there is one.
  final PredictedPeriod? prediction;
}

/// The locale's first weekday, in [MonthGrid]'s convention.
///
/// Flutter reports 0 (Sunday) through 6 (Saturday); [MonthGrid] takes 1 (Monday)
/// through 7 (Sunday). Converted here, once, so no caller has to remember which
/// of the two conventions it is holding. Germany starts the week on Monday and
/// the United States on Sunday, and the calendar has to follow the reader.
int firstWeekdayOf(BuildContext context) {
  final index = MaterialLocalizations.of(context).firstDayOfWeekIndex;
  return index == 0 ? 7 : index;
}

/// A month at a time, with every logged day visible and every past day tappable.
///
/// This screen exists because section 4's whole design assumes users
/// retroactively correct their entries. Without a way to reach a past day, the
/// database supports corrections the interface cannot make.
class CalendarScreen extends StatelessWidget {
  /// Creates the screen.
  const CalendarScreen({
    required this.data,
    required this.grid,
    this.onSelectDay,
    this.onPreviousMonth,
    this.onNextMonth,
    super.key,
  });

  /// The month's computed state.
  final CalendarViewData data;

  /// The month being shown.
  final MonthGrid grid;

  /// Called with the day the user tapped.
  final void Function(CycleDate day)? onSelectDay;

  /// Moves back a month.
  final VoidCallback? onPreviousMonth;

  /// Moves forward a month.
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    final anythingLogged = grid.days.any(
      (day) =>
          grid.isInMonth(day) &&
          (data.loggedDays.contains(day) || data.periodStarts.contains(day)),
    );

    return Scaffold(
      // The month, not the word "Calendar". The tab directly below already says
      // that, so the bar said nothing and the month -- the only part of this
      // screen that changes -- was a smaller heading underneath it. Moving the
      // arrows up with it removes a whole row from a screen that scrolls.
      appBar: AppBar(
        // Grows with the text, so the title can take a second line instead of
        // losing its end. A bar with two icon buttons in it is a much tighter
        // box than the full-width row this replaced: at 200% text on a 320px
        // phone "September 2024" wants 216px and would be given 184, and the
        // year is what gets cut. The grid below clamps rather than wraps
        // because seven columns of digits cannot do this; the month can, and
        // the comment there promises it still scales all the way.
        toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
        // The label goes on the icon, not only in the tooltip: a tooltip is
        // announced when it is shown, and on a touch device it never is, so
        // these two would reach a screen reader as unnamed buttons. They are
        // the only way to move through the calendar.
        leading: IconButton(
          onPressed: onPreviousMonth,
          icon: Icon(Icons.chevron_left, semanticLabel: l10n.previousMonth),
          tooltip: l10n.previousMonth,
        ),
        title: Text(
          DateFormat.yMMMM(locale)
              .format(DateTime(grid.month.year, grid.month.month)),
          maxLines: 2,
        ),
        actions: [
          IconButton(
            onPressed: onNextMonth,
            icon: Icon(Icons.chevron_right, semanticLabel: l10n.nextMonth),
            tooltip: l10n.nextMonth,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            // Seven columns of digits is the one part of this screen that
            // cannot absorb unlimited text scaling: past about 1.3 the numbers
            // are wider than a seventh of a phone and get cut off, which is
            // worse for the user who enlarged them than slightly smaller text
            // would be. Everything outside this grid -- the legend, the month,
            // the empty-month line -- still scales all the way.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                children: [
                  _WeekdayHeader(
                    firstWeekday: grid.firstWeekday,
                    locale: locale,
                  ),
                  const SizedBox(height: 4),
                  for (final week in grid.weeks)
                    Row(
                      children: [
                        for (final day in week)
                          Expanded(
                            child: _DayCell(
                              day: day,
                              inMonth: grid.isInMonth(day),
                              isToday: day == data.today,
                              isPeriodStart: data.periodStarts.contains(day),
                              isLogged: data.loggedDays.contains(day),
                              isEstimated:
                                  data.prediction?.contains(day) ?? false,
                              // Future days are drawn -- the estimated window lives
                              // there and is the reason to look ahead -- but cannot
                              // be logged. This app records what happened, and a
                              // period start dated in the future would invent a
                              // cycle the user has not had, moving every estimate on
                              // the strength of a plan. Passing no callback also
                              // stops a screen reader announcing them as buttons.
                              onTap:
                                  onSelectDay == null || day.isAfter(data.today)
                                  ? null
                                  : () => onSelectDay!(day),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!anythingLogged)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.nothingLoggedThisMonth,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const _Legend(),
          ],
        ),
      ),
    );
  }
}

/// Names every marker the grid uses.
///
/// Not decoration. Section 9 forbids information carried by colour alone, and a
/// calendar is where that rule is easiest to break: a grid of coloured dots is
/// meaningless to anyone who cannot distinguish them. Each state has a distinct
/// shape, and the legend says in words what each shape means.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendEntry(
          label: l10n.legendPeriodStart,
          marker: _Marker(
            filled: true,
            color: theme.colorScheme.primary,
            child: Text(
              '1',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
        _LegendEntry(
          label: l10n.legendLogged,
          marker: _Marker(
            color: theme.colorScheme.onSurfaceVariant,
            child: const _LoggedDot(),
          ),
        ),
        _LegendEntry(
          label: l10n.legendEstimated,
          marker: _Marker(
            strokeWidth: 1,
            color: theme.colorScheme.primary,
            child: const SizedBox.shrink(),
          ),
        ),
        _LegendEntry(
          label: l10n.today,
          marker: _Marker(
            strokeWidth: 2,
            color: theme.colorScheme.onSurface,
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.label, required this.marker});

  final String label;
  final Widget marker;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      marker,
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.color,
    required this.child,
    this.filled = false,
    this.strokeWidth = 0,
  });

  final Color color;
  final Widget child;
  final bool filled;

  /// Zero for no ring. Matches the ring the day cell draws for the same state,
  /// which is the whole point of a legend.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? color : null,
      border: strokeWidth == 0
          ? null
          : Border.all(
              color: color,
              width: strokeWidth,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
    ),
    child: child,
  );
}

/// The small dot marking a day with an entry.
class _LoggedDot extends StatelessWidget {
  const _LoggedDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.firstWeekday, required this.locale});

  /// 1 (Monday) through 7 (Sunday), matching [MonthGrid].
  final int firstWeekday;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat.E(locale);

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                // January 2024 began on a Monday, so the day of the month and
                // the weekday number line up: the 1st is weekday 1, the 7th is
                // weekday 7.
                format.format(
                  DateTime(2024, 1, (firstWeekday - 1 + i) % 7 + 1),
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One day in the grid.
///
/// Four states can be true at once, so they are drawn with different features
/// rather than different colours of the same feature: a period start fills the
/// circle, today outlines it, an estimated day dashes the outline, and a logged
/// day puts a dot beneath the number. The spoken label lists whichever apply,
/// because none of that reaches a screen reader.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isPeriodStart,
    required this.isLogged,
    required this.isEstimated,
    this.onTap,
  });

  final CycleDate day;
  final bool inMonth;
  final bool isToday;
  final bool isPeriodStart;
  final bool isLogged;
  final bool isEstimated;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    final markers = [
      if (isToday) l10n.today,
      if (isPeriodStart) l10n.legendPeriodStart,
      if (isLogged && !isPeriodStart) l10n.legendLogged,
      if (isEstimated) l10n.legendEstimated,
    ];

    final label = l10n.dayAccessibility(
      DateFormat.yMMMMd(locale).format(DateTime(day.year, day.month, day.day)),
      markers.isEmpty ? '' : ', ${markers.join(', ')}',
    );

    // Follows the text rather than a fixed 36: at a larger text size a fixed
    // circle clips the number it exists to display, and the day of the month is
    // the one thing on this screen a user cannot do without.
    final diameter = MediaQuery.textScalerOf(context).scale(36);
    final faded = !inMonth;
    final numberColour = isPeriodStart
        ? theme.colorScheme.onPrimary
        : faded
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : theme.colorScheme.onSurface;

    return Semantics(
      label: label,
      button: onTap != null,
      excludeSemantics: true,
      // Its own node, explicitly. Without this, cells carrying no action --
      // every day from tomorrow onwards -- are merged into their neighbours,
      // and a screen reader reads a whole week as one run-on sentence instead
      // of seven days a user can move between. It reads correctly on a past
      // week and wrongly on a future one, which is exactly the kind of bug
      // that ships.
      container: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: diameter,
                height: diameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPeriodStart ? theme.colorScheme.primary : null,
                  border: isToday
                      ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                      : isEstimated
                      ? Border.all(color: theme.colorScheme.primary)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: numberColour,
                    fontWeight: isToday ? FontWeight.bold : null,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Reserved whether or not it is drawn, so rows do not shift as
              // days get logged.
              SizedBox(
                height: 5,
                child: isLogged && !isPeriodStart
                    ? const _LoggedDot()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
