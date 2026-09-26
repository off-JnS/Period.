import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The kinds of band a day can carry.
enum CalendarMarker { period, estimated, fertile }

/// The colours of the bands, from the theme.
class MarkerColors {
  /// Creates the colours.
  const MarkerColors({
    required this.period,
    required this.estimateLine,
    required this.estimateWash,
    required this.fertile,
  });

  /// The colours for [scheme].
  factory MarkerColors.of(ColorScheme scheme) => MarkerColors(
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
class BandPainter extends CustomPainter {
  const BandPainter({
    required this.marker,
    required this.joinsLeft,
    required this.joinsRight,
    required this.colors,
    required this.scale,
  });

  final CalendarMarker? marker;
  final bool joinsLeft;
  final bool joinsRight;
  final MarkerColors colors;
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
      case CalendarMarker.period:
        canvas.drawRRect(shape, Paint()..color = colors.period);
      case CalendarMarker.fertile:
        canvas.drawRRect(shape, Paint()..color = colors.fertile);
      case CalendarMarker.estimated:
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
  bool shouldRepaint(BandPainter old) =>
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
class MarkerSwatch extends StatelessWidget {
  /// Creates the swatch.
  const MarkerSwatch(this.marker, {this.size = 22, super.key});

  final CalendarMarker marker;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size * 1.5,
      height: size + 8,
      child: CustomPaint(
        painter: BandPainter(
          marker: marker,
          joinsLeft: false,
          joinsRight: false,
          colors: MarkerColors.of(Theme.of(context).colorScheme),
          scale: size / 36,
        ),
      ),
    ),
  );
}

