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
    // Every band is a shade of the app's own rose; the shapes tell them
    // apart (filled, dashed, plain), the shade only agrees with them.
    estimateLine: scheme.primary.withValues(alpha: 0.75),
    // Solid, pre-blended onto the card: a see-through wash would darken
    // where neighbouring days overlap.
    estimateWash: Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.10),
      scheme.groupedCard,
    ),
    fertile: Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.20),
      scheme.groupedCard,
    ),
  );

  final Color period;
  final Color estimateLine;
  final Color estimateWash;
  final Color fertile;
}

/// Draws a day's piece of a band: rounded where the band begins, square and
/// running to the cell edge where it continues into the next day, and fading
/// out on its last day.
///
/// The fade is the point: a period, an estimate or a fertile window does not
/// stop on the stroke of midnight, and a hard edge would claim it does. The
/// day number sits on the solid part, so it stays legible.
class BandPainter extends CustomPainter {
  const BandPainter({
    required this.marker,
    required this.joinsLeft,
    required this.joinsRight,
    required this.colors,
    required this.scale,
    this.fadesOut = false,
  });

  /// Whether this is the band's last day, so it fades out to the right
  /// rather than ending in a rounded cap.
  final bool fadesOut;

  final CalendarMarker? marker;
  final bool joinsLeft;
  final bool joinsRight;
  final MarkerColors colors;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final kind = marker;
    if (kind == null) return;

    final height = math.min(size.height - 8, 46 * scale);
    if (height <= 0) return;
    final top = (size.height - height) / 2;
    const inset = 3.0;
    // Never rounder than the cell is wide: at large text sizes the band
    // grows taller than a day is wide, and a full half-height cap would
    // overlap itself.
    final cap = math.min(height / 2, size.width / 2 - inset);
    final radius = Radius.circular(cap);
    // A joined side reaches half a pixel past the cell, so neighbouring
    // pieces overlap instead of leaving an anti-aliased seam between days.
    final openRight = joinsRight || fadesOut;
    final rect = Rect.fromLTRB(
      joinsLeft ? -0.5 : inset,
      top,
      openRight ? size.width + (joinsRight ? 0.5 : 0) : size.width - inset,
      top + height,
    );
    final shape = RRect.fromRectAndCorners(
      rect,
      topLeft: joinsLeft ? Radius.zero : radius,
      bottomLeft: joinsLeft ? Radius.zero : radius,
      topRight: openRight ? Radius.zero : radius,
      bottomRight: openRight ? Radius.zero : radius,
    );

    // Solid under the number, then fading to nothing at the cell's edge.
    Paint fill(Color color) {
      final paint = Paint()..color = color;
      if (fadesOut) {
        paint.shader = LinearGradient(
          colors: [color, color, color.withValues(alpha: 0)],
          stops: const [0, 0.58, 1],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      }
      return paint;
    }

    switch (kind) {
      case CalendarMarker.period:
        canvas.drawRRect(shape, fill(colors.period));
      case CalendarMarker.fertile:
        canvas.drawRRect(shape, fill(colors.fertile));
      case CalendarMarker.estimated:
        canvas.drawRRect(shape, fill(colors.estimateWash));
        _dashedOutline(canvas, rect, cap, fill(colors.estimateLine), openRight);
    }
  }

  /// The estimate's outline, dashed, left open where the band continues so
  /// the dashes run on across days instead of boxing each one in.
  void _dashedOutline(
    Canvas canvas,
    Rect rect,
    double cap,
    Paint paint,
    bool openRight,
  ) {
    final inner = rect.deflate(0.9);
    final r = math.max(cap - 0.9, 0.0);
    final leftX = joinsLeft ? inner.left : inner.left + r;
    final rightX = openRight ? inner.right : inner.right - r;
    final path = Path()
      ..moveTo(leftX, inner.top)
      ..lineTo(rightX, inner.top);
    // The ends are a quarter arc, a straight side and a quarter arc, which
    // is a plain semicircle when the band is no taller than it is round.
    if (openRight) {
      path.moveTo(rightX, inner.bottom);
    } else {
      path
        ..arcToPoint(
          Offset(inner.right, inner.top + r),
          radius: Radius.circular(r),
        )
        ..lineTo(inner.right, inner.bottom - r)
        ..arcToPoint(Offset(rightX, inner.bottom), radius: Radius.circular(r));
    }
    path.lineTo(leftX, inner.bottom);
    if (!joinsLeft) {
      path
        ..arcToPoint(
          Offset(inner.left, inner.bottom - r),
          radius: Radius.circular(r),
        )
        ..lineTo(inner.left, inner.top + r)
        ..arcToPoint(Offset(leftX, inner.top), radius: Radius.circular(r));
    }

    paint
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
      old.fadesOut != fadesOut ||
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
      width: size * 2,
      height: size + 8,
      child: CustomPaint(
        painter: BandPainter(
          marker: marker,
          joinsLeft: false,
          joinsRight: false,
          fadesOut: true,
          colors: MarkerColors.of(Theme.of(context).colorScheme),
          scale: size / 36,
        ),
      ),
    ),
  );
}
