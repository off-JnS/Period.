import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import 'month_grid.dart';

/// Everything the calendar needs, already computed.
///
/// Like [TodayViewData], results rather than raw rows: the screen renders and
/// nothing else, so every state is reachable in a test without a database.
class CalendarViewData {
  /// Creates the view data.
  const CalendarViewData({
    required this.year,
    required this.month,
    required this.today,
    this.periodStarts = const {},
    this.loggedDays = const {},
    this.predicted,
  });

  /// The month on screen.
  final int year;

  /// The month on screen, 1 through 12.
  final int month;

  /// The day it is now, so today can be marked and the future can be refused.
  final CycleDate today;

  /// Days the user marked as a period start.
  final Set<CycleDate> periodStarts;

  /// Days the user logged anything on.
  final Set<CycleDate> loggedDays;

  /// The estimated next-period window, when there is one.
  final PredictedPeriod? predicted;
}

/// A month at a time, with what was logged and what is estimated.
///
/// Section 9 forbids carrying information by colour alone here specifically, so
/// each state has a shape of its own: a period start is a filled disc, the
/// estimate is a dashed ring, today is a solid ring, and a logged day carries a
/// dot under the number. Colour agrees with the shape but never carries it, and
/// every cell also says its state aloud.
class CalendarScreen extends StatelessWidget {
  /// Creates the screen.
  const CalendarScreen({
    required this.data,
    this.onPreviousMonth,
    this.onNextMonth,
    this.onSelectDay,
    super.key,
  });

  /// The month to render.
  final CalendarViewData data;

  /// Moves back one month.
  final VoidCallback? onPreviousMonth;

  /// Moves forward one month.
  final VoidCallback? onNextMonth;

  /// Opens a day for logging. Never called for a day in the future.
  final void Function(CycleDate date)? onSelectDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    final grid = monthGrid(
      year: data.year,
      month: data.month,
      firstDayOfWeekIndex: materialL10n.firstDayOfWeekIndex,
    );

    final monthLabel = DateFormat.yMMMM(locale)
        .format(DateTime(data.year, data.month));

    return GroupedPage(
      title: l10n.calendarTitle,
      children: [
        _MonthHeader(
          label: monthLabel,
          onPrevious: onPreviousMonth,
          onNext: onNextMonth,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
            child: Column(
              children: [
                _WeekdayHeader(
                  firstDayOfWeekIndex: materialL10n.firstDayOfWeekIndex,
                  narrowWeekdays: materialL10n.narrowWeekdays,
                ),
                const SizedBox(height: 8),
                for (final week in grid.weeks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        for (final day in week)
                          Expanded(
                            child: _DayCell(
                              date: day,
                              inMonth: grid.isInMonth(day),
                              isToday: day == data.today,
                              isFuture: day.isAfter(data.today),
                              isPeriodStart: data.periodStarts.contains(day),
                              isLogged: data.loggedDays.contains(day),
                              isEstimated:
                                  data.predicted?.contains(day) ?? false,
                              onTap: onSelectDay,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _Legend(),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label, this.onPrevious, this.onNext});

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final theme = Theme.of(context);

    return Row(
      children: [
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onPrevious,
          child: Semantics(
            label: l10n.previousMonth,
            child: const Icon(Icons.chevron_left_rounded, size: 30),
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onNext,
          child: Semantics(
            label: l10n.nextMonth,
            child: const Icon(Icons.chevron_right_rounded, size: 30),
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({
    required this.firstDayOfWeekIndex,
    required this.narrowWeekdays,
  });

  final int firstDayOfWeekIndex;
  final List<String> narrowWeekdays;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: ExcludeSemantics(
              // The day cells each say their own full date, so reading seven
              // one-letter headers first would only add noise.
              child: Text(
                narrowWeekdays[(firstDayOfWeekIndex + i) % 7],
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.isFuture,
    required this.isPeriodStart,
    required this.isLogged,
    required this.isEstimated,
    this.onTap,
  });

  final CycleDate date;
  final bool inMonth;
  final bool isToday;
  final bool isFuture;
  final bool isPeriodStart;
  final bool isLogged;
  final bool isEstimated;
  final void Function(CycleDate date)? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final extent = 44.0 * scale;

    final foreground = switch ((isPeriodStart, inMonth)) {
      (true, _) => theme.colorScheme.onPrimary,
      (false, true) => theme.colorScheme.onSurface,
      (false, false) => theme.colorScheme.onSurfaceVariant.withValues(
        alpha: 0.5,
      ),
    };

    // Everything a screen reader needs, in words, because none of the shapes
    // below mean anything to one.
    final spoken = <String>[
      DateFormat.yMMMMd(locale)
          .format(DateTime(date.year, date.month, date.day)),
      if (isToday) l10n.todayTitle,
      if (isPeriodStart) l10n.legendPeriodStart,
      if (isLogged && !isPeriodStart) l10n.legendLogged,
      if (isEstimated) l10n.legendEstimated,
      if (isFuture) l10n.dayNotYetHappened,
    ].join(', ');

    return Semantics(
      label: spoken,
      button: !isFuture && onTap != null,
      excludeSemantics: true,
      child: InkResponse(
        // A future day is not an observation yet, so it cannot be logged. The
        // cell stays visible and still speaks; it simply does not respond.
        onTap: isFuture || onTap == null ? null : () => onTap!(date),
        radius: extent / 2,
        child: SizedBox(
          height: extent,
          child: CustomPaint(
            painter: _DayMarkerPainter(
              filled: isPeriodStart,
              dashedRing: isEstimated && !isPeriodStart,
              solidRing: isToday && !isPeriodStart,
              fill: theme.colorScheme.primary,
              ring: theme.colorScheme.primary,
              dash: theme.colorScheme.tertiary,
              wash: theme.colorScheme.tertiaryContainer,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${date.day}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isFuture
                          ? foreground.withValues(alpha: 0.45)
                          : foreground,
                      fontWeight: isToday || isPeriodStart
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  // The logged marker is a shape under the number rather than a
                  // tint of the cell, so it survives being seen by someone who
                  // cannot tell the tints apart.
                  SizedBox(
                    height: 6 * scale,
                    child: isLogged
                        ? Icon(
                            Icons.circle,
                            size: 5 * scale,
                            color: isPeriodStart
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the disc and rings behind a day number.
class _DayMarkerPainter extends CustomPainter {
  const _DayMarkerPainter({
    required this.filled,
    required this.dashedRing,
    required this.solidRing,
    required this.fill,
    required this.ring,
    required this.dash,
    required this.wash,
  });

  final bool filled;
  final bool dashedRing;
  final bool solidRing;
  final Color fill;
  final Color ring;
  final Color dash;

  /// A soft fill under the estimate's dashes. It agrees with the dashes and
  /// never replaces them: the shape is what carries the state.
  final Color wash;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - 3;
    if (radius <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);

    if (filled) {
      canvas.drawCircle(centre, radius, Paint()..color = fill);
      return;
    }

    if (solidRing) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    if (dashedRing) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()..color = wash.withValues(alpha: 0.7),
      );

      // Dashes rather than a second solid ring: today and the estimate must be
      // told apart by shape, not only by which colour the ring is.
      final paint = Paint()
        ..color = dash
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      const dashes = 12;
      const sweep = math.pi * 2 / dashes;
      final rect = Rect.fromCircle(
        center: centre,
        radius: solidRing ? radius - 4 : radius,
      );
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DayMarkerPainter old) =>
      old.filled != filled ||
      old.dashedRing != dashedRing ||
      old.solidRing != solidRing ||
      old.fill != fill ||
      old.ring != ring ||
      old.dash != dash ||
      old.wash != wash;
}

/// Names every marker in words.
///
/// Not decoration: it is what makes the shapes legible to someone who has not
/// used the app before, and it is the written half of section 9's rule that no
/// state is carried by colour alone.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    _DayMarkerPainter marker({
      bool filled = false,
      bool dashedRing = false,
      bool solidRing = false,
    }) => _DayMarkerPainter(
      filled: filled,
      dashedRing: dashedRing,
      solidRing: solidRing,
      fill: scheme.primary,
      ring: scheme.primary,
      dash: scheme.tertiary,
      wash: scheme.tertiaryContainer,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            _LegendItem(
              label: l10n.legendPeriodStart,
              painter: marker(filled: true),
            ),
            _LegendItem(
              label: l10n.todayTitle,
              painter: marker(solidRing: true),
            ),
            _LegendItem(
              label: l10n.legendEstimated,
              painter: marker(dashedRing: true),
            ),
            _LegendItem(label: l10n.legendLogged, dot: true),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, this.painter, this.dot = false});

  final String label;
  final CustomPainter? painter;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: dot
              ? Center(
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: theme.colorScheme.primary,
                  ),
                )
              : CustomPaint(painter: painter),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
