import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'calendar_markers.dart';
import 'calendar_screen.dart';
import 'month_grid.dart';

/// Whole years at a glance, twelve small months each, as iOS Calendar shows
/// when zoomed out. Tapping a month opens it in the month view.
///
/// The same shapes as the months carry the same states, only smaller: a
/// period day is a filled disc, an estimated one a ring, a fertile one a
/// pale disc with no ring, and today a small rounded square in ink, a shape
/// of its own.
class CalendarYearView extends StatefulWidget {
  /// Creates the view.
  const CalendarYearView({
    required this.data,
    required this.year,
    required this.firstYear,
    required this.lastYear,
    required this.onSelectMonth,
    super.key,
  });

  /// What to draw.
  final CalendarViewData data;

  /// The year shown first, at the top.
  final int year;

  /// The earliest and latest years it scrolls to.
  final int firstYear;
  final int lastYear;

  /// Opens a month, given its year and month.
  final void Function(int year, int month) onSelectMonth;

  @override
  State<CalendarYearView> createState() => _CalendarYearViewState();
}

class _CalendarYearViewState extends State<CalendarYearView> {
  final _centreKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    Widget year(int value) => _Year(
      key: ValueKey(value),
      year: value,
      data: widget.data,
      firstDayOfWeekIndex: firstDay,
      onSelectMonth: widget.onSelectMonth,
    );

    // Anchored on the year shown first, growing both ways from it, as the
    // month view does.
    return CustomScrollView(
      center: _centreKey,
      slivers: [
        SliverList.builder(
          itemCount: widget.year - widget.firstYear,
          itemBuilder: (context, index) => year(widget.year - 1 - index),
        ),
        SliverPadding(
          key: _centreKey,
          // Clear of the dock, which floats over the end.
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.builder(
            itemCount: widget.lastYear + 1 - widget.year,
            itemBuilder: (context, index) => year(widget.year + index),
          ),
        ),
      ],
    );
  }
}

class _Year extends StatelessWidget {
  const _Year({
    required this.year,
    required this.data,
    required this.firstDayOfWeekIndex,
    required this.onSelectMonth,
    super.key,
  });

  final int year;
  final CalendarViewData data;
  final int firstDayOfWeekIndex;
  final void Function(int year, int month) onSelectMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '$year',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: year == data.today.year
                    ? scheme.primary
                    : scheme.onSurface,
              ),
            ),
          ),
          Divider(height: 16, thickness: 0.5, color: scheme.outlineVariant),
          for (var row = 0; row < 4; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < 3; column++) ...[
                    if (column > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _MiniMonth(
                        year: year,
                        month: row * 3 + column + 1,
                        data: data,
                        firstDayOfWeekIndex: firstDayOfWeekIndex,
                        onTap: () => onSelectMonth(year, row * 3 + column + 1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.year,
    required this.month,
    required this.data,
    required this.firstDayOfWeekIndex,
    required this.onTap,
  });

  final int year;
  final int month;
  final CalendarViewData data;
  final int firstDayOfWeekIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final colors = MarkerColors.of(
      scheme,
      background: scheme.groupedBackground,
    );
    final today = data.today;
    final isCurrent = year == today.year && month == today.month;
    final grid = monthGrid(
      year: year,
      month: month,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );
    final first = DateTime(year, month);

    return Semantics(
      button: true,
      label: DateFormat.yMMMM(locale).format(first),
      hint: l10n.calendarOpenMonth,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                DateFormat.MMM(locale).format(first),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            // Fixed at six rows, so every month in a row lines up.
            for (var week = 0; week < 6; week++)
              Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: switch (week * 7 + column) {
                          final i
                              when i < grid.days.length &&
                                  grid.isInMonth(grid.days[i]) =>
                            _MiniDay(
                              day: grid.days[i],
                              data: data,
                              colors: colors,
                            ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({required this.day, required this.data, required this.colors});

  final CycleDate day;
  final CalendarViewData data;
  final MarkerColors colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marker = data.markerOn(day);
    final isToday = day == data.today;
    final onPeriod = marker == CalendarMarker.period;
    final future = day.isAfter(data.today);

    return Padding(
      padding: const EdgeInsets.all(0.5),
      child: DecoratedBox(
        decoration: isToday
            ? BoxDecoration(
                color: scheme.onSurface,
                borderRadius: BorderRadius.circular(3),
              )
            : BoxDecoration(
                shape: BoxShape.circle,
                color: switch (marker) {
                  CalendarMarker.period => colors.period,
                  CalendarMarker.fertile => colors.fertile,
                  _ => null,
                },
                border: marker == CalendarMarker.estimated
                    ? Border.all(color: colors.estimateLine, width: 1)
                    : null,
              ),
        child: Center(
          child: FittedBox(
            child: Text(
              '${day.day}',
              // Held at its size: a year of months cannot grow with the text
              // and still fit, and each month reads aloud as a whole anyway.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 9,
                height: 1,
                fontWeight: isToday || onPeriod
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: isToday
                    ? scheme.surface
                    : onPeriod
                    ? scheme.onPrimary
                    : future
                    ? scheme.onSurface.withValues(alpha: 0.45)
                    : scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
