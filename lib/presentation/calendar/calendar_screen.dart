import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/calendar_month.dart';
import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'calendar_markers.dart';
import 'month_grid.dart';

/// Everything the calendar needs, already computed.
///
/// Like [TodayViewData], results rather than raw rows: the screen renders and
/// nothing else, so every state is reachable in a test without a database.
class CalendarViewData {
  /// Creates the view data.
  const CalendarViewData({
    required this.today,
    this.periodStarts = const {},
    this.flowByDay = const {},
    this.loggedDays = const {},
    this.sexDays = const {},
    this.pregnancyTestDays = const {},
    this.predicted,
    this.fertileWindow,
  });

  /// The day it is now: the calendar opens on its month, marks it, and
  /// refuses the days after it.
  final CycleDate today;

  /// Days she marked as a period start.
  final Set<CycleDate> periodStarts;

  /// The flow she logged, by day.
  final Map<CycleDate, FlowIntensity> flowByDay;

  /// Days she logged anything on.
  final Set<CycleDate> loggedDays;

  /// Days she recorded having sex, protected or not.
  final Set<CycleDate> sexDays;

  /// Days she recorded a pregnancy test, whatever the result: the mark says
  /// a test was taken, never what it showed.
  final Set<CycleDate> pregnancyTestDays;

  /// The estimated next-period window, when there is one.
  final PredictedPeriod? predicted;

  /// The estimated fertile window, only when she opted in and there is an
  /// estimate to count back from.
  final FertileWindowEstimate? fertileWindow;

  /// Whether [date] is drawn as a period day.
  bool isPeriod(CycleDate date) =>
      isPeriodDay(date, starts: periodStarts, flowByDay: flowByDay);

  /// Whether [date] lies in the estimated window and is not already a
  /// logged period day.
  bool isEstimated(CycleDate date) =>
      (predicted?.contains(date) ?? false) && !isPeriod(date);

  /// Whether [date] lies in the estimated fertile window.
  bool isFertile(CycleDate date) =>
      (fertileWindow?.contains(date) ?? false) &&
      !isPeriod(date) &&
      !isEstimated(date);

  /// The band drawn on [date], if any.
  CalendarMarker? markerOn(CycleDate date) {
    if (isPeriod(date)) return CalendarMarker.period;
    if (isEstimated(date)) return CalendarMarker.estimated;
    if (isFertile(date)) return CalendarMarker.fertile;
    return null;
  }
}

/// Every month in one continuous scroll, the current one first on screen.
///
/// Scrolls in both directions: back through her history, forward through the
/// estimate. Months are built only as they come into view.
///
/// Section 9 forbids carrying information by colour alone here specifically,
/// so each state has a shape of its own: a period is a filled band, the
/// estimated period a dashed outline, the fertile window a band with no
/// outline, today a ring around the number, and a logged day a dot under it.
/// Every cell also says its state aloud, and tapping a day shows it in words.
class CalendarScreen extends StatefulWidget {
  /// Creates the screen.
  const CalendarScreen({required this.data, this.onSelectDay, super.key});

  /// What to draw.
  final CalendarViewData data;

  /// Shows a day. Called for any day, future ones included, which have an
  /// estimate to show even though they cannot be logged yet.
  final void Function(CycleDate date)? onSelectDay;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

/// The earliest year the calendar scrolls back to.
const _firstYear = 1900;

/// The last year the calendar scrolls forward to.
const _lastYear = 2199;

class _CalendarScreenState extends State<CalendarScreen> {
  final _controller = ScrollController();

  /// The sliver the scroll is anchored on: the current month, at offset 0.
  final _centreKey = UniqueKey();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Back to the current month: a glide when it is near, a jump when it is
  /// years away, where a glide would only be a blur.
  void _scrollToToday() {
    if (!_controller.hasClients) return;
    HapticFeedback.selectionClick();
    if (_controller.offset.abs() > 4000) {
      _controller.jumpTo(0);
    } else {
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final materialL10n = MaterialLocalizations.of(context);
    final today = widget.data.today;
    final current = today.year * 12 + today.month - 1;

    Widget month(int absolute) => _MonthSection(
      key: ValueKey(absolute),
      year: absolute ~/ 12,
      month: absolute % 12 + 1,
      data: widget.data,
      firstDayOfWeekIndex: materialL10n.firstDayOfWeekIndex,
      onSelectDay: widget.onSelectDay,
    );

    return Scaffold(
      backgroundColor: scheme.groupedCard,
      body: Column(
        children: [
          // A fixed bar rather than a collapsing one: the scroll runs both
          // ways from the middle, so a large title in it would sit above the
          // earliest month instead of at the top of the screen.
          Material(
            color: scheme.groupedCard,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              l10n.calendarTitle,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(44, 44),
                          onPressed: _scrollToToday,
                          child: Text(
                            l10n.todayTitle,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: l10n.calendarLegendButton,
                          excludeSemantics: true,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            onPressed: () => _showLegend(
                              context,
                              showFertile: widget.data.fertileWindow != null,
                            ),
                            child: Icon(
                              CupertinoIcons.info_circle,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: _WeekdayHeader(
                      firstDayOfWeekIndex: materialL10n.firstDayOfWeekIndex,
                      narrowWeekdays: materialL10n.narrowWeekdays,
                    ),
                  ),
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: scheme.outlineVariant,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              controller: _controller,
              center: _centreKey,
              slivers: [
                // Grows upwards from the current month, into the past.
                SliverList.builder(
                  itemCount: current - _firstYear * 12,
                  itemBuilder: (context, index) => month(current - 1 - index),
                ),
                // The current month and everything after it.
                SliverPadding(
                  key: _centreKey,
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList.builder(
                    itemCount: (_lastYear + 1) * 12 - current,
                    itemBuilder: (context, index) => month(current + index),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One month: its name, a line for each thing it holds, and its days.
class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.year,
    required this.month,
    required this.data,
    required this.firstDayOfWeekIndex,
    this.onSelectDay,
    super.key,
  });

  final int year;
  final int month;
  final CalendarViewData data;
  final int firstDayOfWeekIndex;
  final void Function(CycleDate date)? onSelectDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = data.today;
    final isCurrent = year == today.year && month == today.month;

    final grid = monthGrid(
      year: year,
      month: month,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );
    final title = DateFormat(
      year == today.year ? 'MMMM' : 'yMMMM',
      locale,
    ).format(DateTime(year, month));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the column of the 1st, as iOS Calendar places it, so the
          // name leads straight into the month's first day.
          LayoutBuilder(
            builder: (context, constraints) {
              final lead = grid.days.indexWhere(grid.isInMonth);
              final column = constraints.maxWidth / 7;
              return Padding(
                padding: EdgeInsetsDirectional.only(
                  start: math
                      .min(
                        lead * column + column / 2 - 12,
                        constraints.maxWidth / 2,
                      )
                      .clamp(4.0, double.infinity),
                  bottom: 6,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
          for (final week in grid.weeks)
            Row(
              children: [
                for (final (column, date) in week.indexed)
                  Expanded(
                    child: grid.isInMonth(date)
                        ? _DayCell(
                            date: date,
                            data: data,
                            joinsLeft: column > 0,
                            joinsRight: column < 6,
                            inMonth: grid.isInMonth,
                            onTap: onSelectDay,
                          )
                        // Days of the neighbouring months are left out: each
                        // belongs to its own month, one scroll away.
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      ),
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
                  fontWeight: FontWeight.w600,
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
    required this.data,
    required this.joinsLeft,
    required this.joinsRight,
    required this.inMonth,
    this.onTap,
  });

  final CycleDate date;
  final CalendarViewData data;

  /// Whether the cell has a neighbour on that side in its row, so a band can
  /// run on into it.
  final bool joinsLeft;
  final bool joinsRight;
  final bool Function(CycleDate date) inMonth;
  final void Function(CycleDate date)? onTap;

  CalendarMarker? _markerOn(CycleDate day) => data.markerOn(day);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final extent = 58.0 * scale;

    final isToday = date == data.today;
    final isFuture = date.isAfter(data.today);
    final isLogged = data.loggedDays.contains(date);
    final hadSex = data.sexDays.contains(date);
    final hadTest = data.pregnancyTestDays.contains(date);
    final marker = _markerOn(date);
    final previous = date.subtractDays(1);
    final next = date.addDays(1);
    final left =
        marker != null &&
        joinsLeft &&
        inMonth(previous) &&
        _markerOn(previous) == marker;
    // Whether the band carries on the next day at all, even if into the next
    // row or month. Only where it truly stops does it fade out.
    final continues = marker != null && _markerOn(next) == marker;
    final right = continues && joinsRight && inMonth(next);
    final fadesOut = marker != null && !continues;
    // Weekend numbers in grey, as iOS Calendar sets them.
    final isWeekend = date.weekday >= DateTime.saturday;

    final onBand = marker == CalendarMarker.period;
    final foreground = onBand
        ? scheme.onPrimary
        : isWeekend
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

    // Everything a screen reader needs, in words, because none of the shapes
    // below mean anything to one.
    final spoken = <String>[
      DateFormat.yMMMMd(locale)
          .format(DateTime(date.year, date.month, date.day)),
      if (isToday) l10n.todayTitle,
      if (data.periodStarts.contains(date))
        l10n.legendPeriodStart
      else if (marker == CalendarMarker.period)
        l10n.legendPeriodDay,
      if (isLogged && marker != CalendarMarker.period) l10n.legendLogged,
      if (hadSex) l10n.sexHeading,
      if (hadTest) l10n.pregnancyTestLabel,
      if (marker == CalendarMarker.estimated) l10n.legendEstimated,
      if (marker == CalendarMarker.fertile) l10n.fertileWindowHeading,
      if (isFuture) l10n.dayNotYetHappened,
    ].join(', ');

    return Semantics(
      // Its own node, so each day is reached and read on its own rather than
      // folded into the month around it.
      container: true,
      label: spoken,
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Future days open too: there is an estimate to show, though the
        // preview offers no editing until the day has happened.
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!(date);
              },
        // A hairline above every day, as iOS draws above each week: the
        // first row's starts at the 1st, not at the edge.
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
          ),
          child: SizedBox(
            height: extent,
            child: CustomPaint(
              painter: BandPainter(
                marker: marker,
                joinsLeft: left,
                joinsRight: right,
                fadesOut: fadesOut,
                colors: MarkerColors.of(scheme),
                scale: scale,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The number sits a little above centre, leaving room
                  // beneath it, inside the band, for the day's mark.
                  Align(
                    alignment: const Alignment(0, -0.2),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Today is a filled circle, as in iOS Calendar;
                        // inverted on a period band so it still stands out.
                        if (isToday)
                          Container(
                            width: 32 * scale,
                            height: 32 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: onBand ? scheme.onPrimary : scheme.primary,
                            ),
                          ),
                        Text(
                          '${date.day}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 19,
                            color: isToday
                                ? (onBand ? scheme.primary : scheme.onPrimary)
                                : isFuture && !onBand
                                ? foreground.withValues(alpha: 0.45)
                                : foreground,
                            fontWeight: isToday || onBand
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A shape under the number rather than a tint of the cell,
                  // so it survives being seen by someone who cannot tell the
                  // tints apart. A heart for sex takes the dot's place: it is
                  // a logged day too, and one mark reads cleaner than two.
                  if (hadSex || hadTest || isLogged)
                    Align(
                      alignment: const Alignment(0, 0.6),
                      child: hadSex || hadTest
                          // Icons for the two things worth spotting at a
                          // glance, side by side on a day with both; the
                          // plain dot for anything else logged.
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hadSex)
                                  Icon(
                                    CupertinoIcons.heart_fill,
                                    size: 9 * scale,
                                    color: onBand
                                        ? scheme.onPrimary
                                        : scheme.primary,
                                  ),
                                if (hadSex && hadTest)
                                  SizedBox(width: 2 * scale),
                                if (hadTest)
                                  Icon(
                                    CupertinoIcons.plus_slash_minus,
                                    // The glyph sits small in its box, so it
                                    // needs a larger size to match the heart.
                                    size: 14 * scale,
                                    color: onBand
                                        ? scheme.onPrimary
                                        : scheme.primary,
                                  ),
                              ],
                            )
                          : Container(
                              width: 5 * scale,
                              height: 5 * scale,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: onBand
                                    ? scheme.onPrimary
                                    : scheme.primary,
                              ),
                            ),
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

/// Names every marker in words.
///
/// Not decoration: it is what makes the shapes legible to someone who has not
/// used the app before, and it is the written half of section 9's rule that no
/// state is carried by colour alone. The fertile window's caveat comes with it
/// whenever that band can appear (CLAUDE.md §8).
Future<void> _showLegend(BuildContext context, {required bool showFertile}) {
  final l10n = AppLocalizations.of(context);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.groupedCard,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      Widget item(Widget swatch, String label, [String? detail]) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 44, child: Center(child: swatch)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (detail != null)
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.calendarLegendButton,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              item(
                const MarkerSwatch(CalendarMarker.period),
                l10n.legendPeriodDay,
              ),
              item(
                const MarkerSwatch(CalendarMarker.estimated),
                l10n.legendEstimated,
              ),
              if (showFertile)
                item(
                  const MarkerSwatch(CalendarMarker.fertile),
                  l10n.fertileWindowHeading,
                  l10n.fertileWindowCaveat,
                ),
              item(
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
                l10n.todayTitle,
              ),
              item(
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                  ),
                ),
                l10n.legendLogged,
              ),
              item(
                Icon(
                  CupertinoIcons.heart_fill,
                  size: 12,
                  color: scheme.primary,
                ),
                l10n.sexHeading,
              ),
              item(
                Icon(
                  CupertinoIcons.plus_slash_minus,
                  size: 17,
                  color: scheme.primary,
                ),
                l10n.pregnancyTestLabel,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.legendTapHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
