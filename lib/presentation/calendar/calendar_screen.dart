import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/calendar_month.dart';
import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/period_length.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';
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
/// Every cell also says its state aloud, and each month says in words what it
/// holds.
class CalendarScreen extends StatefulWidget {
  /// Creates the screen.
  const CalendarScreen({required this.data, this.onSelectDay, super.key});

  /// What to draw.
  final CalendarViewData data;

  /// Opens a day for logging. Never called for a day in the future.
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
      backgroundColor: scheme.groupedBackground,
      body: Column(
        children: [
          // A fixed bar rather than a collapsing one: the scroll runs both
          // ways from the middle, so a large title in it would sit above the
          // earliest month instead of at the top of the screen.
          Material(
            color: scheme.groupedBackground,
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
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = data.today;
    final isCurrent = year == today.year && month == today.month;

    String day(CycleDate date) => DateFormat.MMMd(
      locale,
    ).format(DateTime(date.year, date.month, date.day));
    String range(CycleDate from, CycleDate to) =>
        l10n.estimatedRange(day(from), day(to));

    bool touches(CycleDate earliest, CycleDate latest) => rangeTouchesMonth(
      earliest: earliest,
      latest: latest,
      year: year,
      month: month,
    );

    final fertile = data.fertileWindow;
    final predicted = data.predicted;
    final summaries = <(_Marker, String)>[
      for (final period in periodsStartingIn(
        year: year,
        month: month,
        starts: data.periodStarts.toList(),
        flowByDay: data.flowByDay,
        today: today,
      ))
        (
          _Marker.period,
          switch (period.length) {
            KnownPeriodLength(:final days) => l10n.calendarPeriodFinished(
              range(period.start, period.lastDay!),
              l10n.lengthInDays(days),
            ),
            OngoingPeriodLength() => l10n.calendarPeriodOngoing(
              day(period.start),
            ),
            UnknownPeriodLength() => l10n.calendarPeriodStarted(
              day(period.start),
            ),
          },
        ),
      if (fertile != null && touches(fertile.earliest, fertile.latest))
        (
          _Marker.fertile,
          l10n.calendarFertileSummary(range(fertile.earliest, fertile.latest)),
        ),
      if (predicted != null && touches(predicted.earliest, predicted.latest))
        (
          _Marker.estimated,
          l10n.calendarEstimateSummary(
            range(predicted.earliest, predicted.latest),
          ),
        ),
    ];

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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        // Not one merged node: each day has to be reachable and spoken on
        // its own.
        semanticContainer: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
              ),
              if (summaries.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final (marker, text) in summaries)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _MarkerSwatch(marker, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 10),
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
                            // Days of the neighbouring months are left out:
                            // each belongs to its own month, one scroll away.
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
            ],
          ),
        ),
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

/// The kinds of band a day can carry.
enum _Marker { period, estimated, fertile }

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

  _Marker? _markerOn(CycleDate day) {
    if (data.isPeriod(day)) return _Marker.period;
    if (data.isEstimated(day)) return _Marker.estimated;
    if (data.isFertile(day)) return _Marker.fertile;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final extent = 46.0 * scale;

    final isToday = date == data.today;
    final isFuture = date.isAfter(data.today);
    final isLogged = data.loggedDays.contains(date);
    final marker = _markerOn(date);
    final previous = date.subtractDays(1);
    final next = date.addDays(1);
    final left =
        marker != null &&
        joinsLeft &&
        inMonth(previous) &&
        _markerOn(previous) == marker;
    final right =
        marker != null &&
        joinsRight &&
        inMonth(next) &&
        _markerOn(next) == marker;

    final onBand = marker == _Marker.period;
    final foreground = onBand ? scheme.onPrimary : scheme.onSurface;

    // Everything a screen reader needs, in words, because none of the shapes
    // below mean anything to one.
    final spoken = <String>[
      DateFormat.yMMMMd(
        locale,
      ).format(DateTime(date.year, date.month, date.day)),
      if (isToday) l10n.todayTitle,
      if (data.periodStarts.contains(date))
        l10n.legendPeriodStart
      else if (marker == _Marker.period)
        l10n.legendPeriodDay,
      if (isLogged && marker != _Marker.period) l10n.legendLogged,
      if (marker == _Marker.estimated) l10n.legendEstimated,
      if (marker == _Marker.fertile) l10n.fertileWindowHeading,
      if (isFuture) l10n.dayNotYetHappened,
    ].join(', ');

    return Semantics(
      label: spoken,
      button: !isFuture && onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A future day is not an observation yet, so it cannot be logged. The
        // cell stays visible and still speaks; it simply does not respond.
        onTap: isFuture || onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!(date);
              },
        child: SizedBox(
          height: extent,
          child: CustomPaint(
            painter: _BandPainter(
              marker: marker,
              joinsLeft: left,
              joinsRight: right,
              colors: _MarkerColors.of(scheme),
              scale: scale,
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (isToday)
                    Container(
                      width: 32 * scale,
                      height: 32 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: onBand ? scheme.onPrimary : scheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  Text(
                    '${date.day}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isFuture && !onBand
                          ? foreground.withValues(alpha: 0.4)
                          : isToday && !onBand
                          ? scheme.primary
                          : foreground,
                      fontWeight: isToday || onBand
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  // A shape under the number rather than a tint of the cell,
                  // so it survives being seen by someone who cannot tell the
                  // tints apart.
                  if (isLogged)
                    Positioned(
                      bottom: -10 * scale,
                      child: Container(
                        width: 5 * scale,
                        height: 5 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: onBand ? scheme.onPrimary : scheme.primary,
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

class _MarkerColors {
  const _MarkerColors({
    required this.period,
    required this.estimateLine,
    required this.estimateWash,
    required this.fertile,
  });

  factory _MarkerColors.of(ColorScheme scheme) => _MarkerColors(
    period: scheme.primary,
    estimateLine: scheme.tertiary,
    // Solid, pre-blended onto the card: a see-through wash would darken
    // where neighbouring days overlap.
    estimateWash: Color.alphaBlend(
      scheme.tertiaryContainer.withValues(alpha: 0.6),
      scheme.groupedCard,
    ),
    fertile: scheme.secondaryContainer,
  );

  final Color period;
  final Color estimateLine;
  final Color estimateWash;
  final Color fertile;
}

/// Draws a day's piece of a band: rounded where the band ends, square and
/// running to the cell edge where it continues into the next day.
class _BandPainter extends CustomPainter {
  const _BandPainter({
    required this.marker,
    required this.joinsLeft,
    required this.joinsRight,
    required this.colors,
    required this.scale,
  });

  final _Marker? marker;
  final bool joinsLeft;
  final bool joinsRight;
  final _MarkerColors colors;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final kind = marker;
    if (kind == null) return;

    final height = math.min(size.height - 8, 36 * scale);
    if (height <= 0) return;
    final top = (size.height - height) / 2;
    const inset = 3.0;
    final radius = Radius.circular(height / 2);
    // A joined side reaches half a pixel past the cell, so neighbouring
    // pieces overlap instead of leaving an anti-aliased seam between days.
    final rect = Rect.fromLTRB(
      joinsLeft ? -0.5 : inset,
      top,
      joinsRight ? size.width + 0.5 : size.width - inset,
      top + height,
    );
    final shape = RRect.fromRectAndCorners(
      rect,
      topLeft: joinsLeft ? Radius.zero : radius,
      bottomLeft: joinsLeft ? Radius.zero : radius,
      topRight: joinsRight ? Radius.zero : radius,
      bottomRight: joinsRight ? Radius.zero : radius,
    );

    switch (kind) {
      case _Marker.period:
        canvas.drawRRect(shape, Paint()..color = colors.period);
      case _Marker.fertile:
        canvas.drawRRect(shape, Paint()..color = colors.fertile);
      case _Marker.estimated:
        canvas.drawRRect(shape, Paint()..color = colors.estimateWash);
        _dashedOutline(canvas, rect);
    }
  }

  /// The estimate's outline, dashed, left open where the band continues so
  /// the dashes run on across days instead of boxing each one in.
  void _dashedOutline(Canvas canvas, Rect rect) {
    final inner = rect.deflate(0.9);
    final r = inner.height / 2;
    final leftX = joinsLeft ? inner.left : inner.left + r;
    final rightX = joinsRight ? inner.right : inner.right - r;
    final path = Path()
      ..moveTo(leftX, inner.top)
      ..lineTo(rightX, inner.top);
    if (joinsRight) {
      path.moveTo(rightX, inner.bottom);
    } else {
      path.arcToPoint(Offset(rightX, inner.bottom), radius: Radius.circular(r));
    }
    path.lineTo(leftX, inner.bottom);
    if (!joinsLeft) {
      path.arcToPoint(Offset(leftX, inner.top), radius: Radius.circular(r));
    }

    final paint = Paint()
      ..color = colors.estimateLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 3.5;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.marker != marker ||
      old.joinsLeft != joinsLeft ||
      old.joinsRight != joinsRight ||
      old.scale != scale ||
      old.colors.period != colors.period ||
      old.colors.estimateLine != colors.estimateLine ||
      old.colors.estimateWash != colors.estimateWash ||
      old.colors.fertile != colors.fertile;
}

/// A marker on its own, for the month lines and the legend.
class _MarkerSwatch extends StatelessWidget {
  const _MarkerSwatch(this.marker, {this.size = 22});

  final _Marker marker;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size * 1.5,
      height: size + 8,
      child: CustomPaint(
        painter: _BandPainter(
          marker: marker,
          joinsLeft: false,
          joinsRight: false,
          colors: _MarkerColors.of(Theme.of(context).colorScheme),
          scale: size / 36,
        ),
      ),
    ),
  );
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
              item(const _MarkerSwatch(_Marker.period), l10n.legendPeriodDay),
              item(
                const _MarkerSwatch(_Marker.estimated),
                l10n.legendEstimated,
              ),
              if (showFertile)
                item(
                  const _MarkerSwatch(_Marker.fertile),
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
