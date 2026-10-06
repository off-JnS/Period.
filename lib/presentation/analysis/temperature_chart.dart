import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../log/temperature.dart';
import '../section_card.dart';

/// One cycle's temperature readings, by cycle day. Only what was logged; no
/// line, band or label interprets it (docs/cycle-logic.md §9).
class TemperatureChartData {
  /// Creates the data.
  const TemperatureChartData({
    required this.cycleStart,
    required this.days,
    required this.readings,
    required this.positiveTestDays,
  });

  /// The period start the cycle began with.
  final CycleDate cycleStart;

  /// How many days the x axis covers: the cycle's length, or its days so far,
  /// and never fewer than 28 so a young cycle does not stretch.
  final int days;

  /// Cycle day (1-based) to temperature in hundredths of °C.
  final Map<int, int> readings;

  /// Cycle days with a positive ovulation test.
  final Set<int> positiveTestDays;
}

/// The chart for the most recent cycle with any reading, or null when no
/// temperature was ever logged -- then there is nothing to show at all.
TemperatureChartData? temperatureChartFrom({
  required List<CycleDate> periodStarts,
  required Map<CycleDate, int> temperatures,
  required Set<CycleDate> positiveTests,
  required CycleDate today,
}) {
  final starts = [...periodStarts]..sort();
  for (var i = starts.length - 1; i >= 0; i--) {
    final start = starts[i];
    final end = i + 1 < starts.length ? starts[i + 1].subtractDays(1) : today;
    bool inCycle(CycleDate day) => !day.isBefore(start) && !day.isAfter(end);

    final readings = {
      for (final MapEntry(:key, :value) in temperatures.entries)
        if (inCycle(key)) start.daysUntil(key) + 1: value,
    };
    if (readings.isEmpty) continue;
    return TemperatureChartData(
      cycleStart: start,
      days: math.max(28, start.daysUntil(end) + 1),
      readings: readings,
      positiveTestDays: {
        for (final day in positiveTests)
          if (inCycle(day)) start.daysUntil(day) + 1,
      },
    );
  }
  return null;
}

/// The chart card on the cycles screen.
class TemperatureChartCard extends StatelessWidget {
  /// Creates the card.
  const TemperatureChartCard({required this.data, super.key});

  /// What to draw.
  final TemperatureChartData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final values = data.readings.values;
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final start = DateFormat.MMMd(locale).format(
      DateTime(
        data.cycleStart.year,
        data.cycleStart.month,
        data.cycleStart.day,
      ),
    );
    final caption = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SectionCard(
      icon: Icons.thermostat_rounded,
      heading: l10n.temperatureChartHeading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.temperatureChartSince(start), style: caption),
          const SizedBox(height: 12),
          if (data.readings.length < 2)
            Text(
              l10n.temperatureChartNeedMore,
              style: theme.textTheme.bodyLarge,
            )
          else ...[
            Semantics(
              label: l10n.temperatureChartLabel(
                data.readings.length,
                formatTemperature(low, locale),
                formatTemperature(high, locale),
              ),
              excludeSemantics: true,
              child: SizedBox(
                height: 160,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TemperaturePainter(
                    data: data,
                    line: scheme.primary,
                    grid: scheme.outlineVariant,
                    marker: scheme.tertiary,
                    label: caption ?? const TextStyle(),
                    lowLabel: formatTemperature(low, locale),
                    highLabel: formatTemperature(high, locale),
                    firstDayLabel: l10n.cycleDayAxis(1),
                    lastDayLabel: l10n.cycleDayAxis(data.days),
                  ),
                ),
              ),
            ),
            if (data.positiveTestDays.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  CustomPaint(
                    size: const Size(12, 10),
                    painter: _TrianglePainter(scheme.tertiary),
                  ),
                  const SizedBox(width: 6),
                  Text(l10n.positiveTestLegend, style: caption),
                ],
              ),
            ],
          ],
          const SizedBox(height: 10),
          // Said beside the chart, as docs/cycle-logic.md §9 requires.
          Text(l10n.temperatureChartNote, style: caption),
        ],
      ),
    );
  }
}

class _TemperaturePainter extends CustomPainter {
  const _TemperaturePainter({
    required this.data,
    required this.line,
    required this.grid,
    required this.marker,
    required this.label,
    required this.lowLabel,
    required this.highLabel,
    required this.firstDayLabel,
    required this.lastDayLabel,
  });

  final TemperatureChartData data;
  final Color line;
  final Color grid;
  final Color marker;
  final TextStyle label;
  final String lowLabel;
  final String highLabel;
  final String firstDayLabel;
  final String lastDayLabel;

  @override
  void paint(Canvas canvas, Size size) {
    TextPainter text(String value) => TextPainter(
      text: TextSpan(text: value, style: label),
      textDirection: TextDirection.ltr,
    )..layout();

    final high = text(highLabel);
    final low = text(lowLabel);
    final first = text(firstDayLabel);
    final last = text(lastDayLabel);

    final left = math.max(high.width, low.width) + 8;
    const top = 8.0;
    final bottom = size.height - first.height - 6;
    final right = size.width - 4;

    final values = data.readings.values;
    // A tenth of a degree of air above and below, so the extremes do not sit
    // on the frame.
    final minY = values.reduce(math.min) - 10;
    final maxY = values.reduce(math.max) + 10;

    double x(int day) =>
        left + (right - left) * (day - 1) / math.max(1, data.days - 1);
    double y(int centi) =>
        bottom - (bottom - top) * (centi - minY) / math.max(1, maxY - minY);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    canvas
      ..drawLine(
        Offset(left, y(values.reduce(math.max))),
        Offset(right, y(values.reduce(math.max))),
        gridPaint,
      )
      ..drawLine(
        Offset(left, y(values.reduce(math.min))),
        Offset(right, y(values.reduce(math.min))),
        gridPaint,
      )
      ..drawLine(Offset(left, bottom), Offset(right, bottom), gridPaint);

    high.paint(canvas, Offset(0, y(values.reduce(math.max)) - high.height / 2));
    low.paint(canvas, Offset(0, y(values.reduce(math.min)) - low.height / 2));
    first.paint(canvas, Offset(left, bottom + 4));
    last.paint(canvas, Offset(right - last.width, bottom + 4));

    // Readings joined only across consecutive days: a gap stays a gap rather
    // than a line inventing the days in between.
    final days = data.readings.keys.toList()..sort();
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < days.length; i++) {
      if (days[i] - days[i - 1] != 1) continue;
      canvas.drawLine(
        Offset(x(days[i - 1]), y(data.readings[days[i - 1]]!)),
        Offset(x(days[i]), y(data.readings[days[i]]!)),
        linePaint,
      );
    }
    final dot = Paint()..color = line;
    for (final day in days) {
      canvas.drawCircle(Offset(x(day), y(data.readings[day]!)), 3.5, dot);
    }

    // Positive tests: a triangle along the top, a shape as well as a colour.
    for (final day in data.positiveTestDays) {
      if (day < 1 || day > data.days) continue;
      _TrianglePainter.draw(canvas, Offset(x(day), top), marker);
    }
  }

  @override
  bool shouldRepaint(_TemperaturePainter old) =>
      old.data != data || old.line != line || old.label != label;
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  static void draw(Canvas canvas, Offset centre, Color color) {
    final path = Path()
      ..moveTo(centre.dx, centre.dy + 4)
      ..lineTo(centre.dx - 5, centre.dy - 4)
      ..lineTo(centre.dx + 5, centre.dy - 4)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) =>
      draw(canvas, Offset(size.width / 2, size.height / 2), color);

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
