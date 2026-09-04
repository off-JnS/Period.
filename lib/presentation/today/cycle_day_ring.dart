import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The cycle-day ring on the Today screen.
///
/// Design notes worth keeping, because each is load-bearing rather than taste:
///
/// - **The number is the content; the ring is decoration.** Section 9 forbids
///   carrying information by colour alone, and the same reasoning applies to
///   shape: the day is written in the middle in plain text, so the arc adds
///   emphasis without ever being the only way to read the value.
/// - **It carries a spoken label.** An arc conveys nothing to a screen reader,
///   so the whole widget is one semantics node that says the value aloud.
/// - **It scales with text.** The ring is sized from the text scale factor, so
///   a user at 200% text size gets a bigger ring rather than a clipped number.
/// - **Colours come from the theme**, so light and dark and the platform's
///   increase-contrast setting are all handled without a second palette.
class CycleDayRing extends StatelessWidget {
  /// Creates the ring.
  const CycleDayRing({required this.day, this.expectedLength, super.key});

  /// The current cycle day, or null when no cycle is in progress.
  final int? day;

  /// The user's typical cycle length, used only to decide how far round the arc
  /// is drawn. Null leaves the arc at a neutral fraction: an unknown length must
  /// not be quietly rendered as 28.
  final int? expectedLength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currentDay = day;

    final label = currentDay == null
        ? l10n.noCycleInProgress
        : l10n.cycleDay(currentDay);
    final spoken = currentDay == null
        ? l10n.noCycleInProgress
        : l10n.cycleDayAccessibility(currentDay);

    // Grow with the user's text size rather than clipping. Capped so that a very
    // large setting does not push everything else off the screen.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final diameter = 180.0 * scale;

    final length = expectedLength;
    // Deliberately NOT clamped to 1. Past the usual length the ring would
    // otherwise look identical to a cycle finishing exactly on time, and "am I
    // late" is the most common reason to open this screen at all.
    final progress = currentDay == null || length == null || length <= 0
        ? null
        : currentDay / length;

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _RingPainter(
            progress: progress,
            track: theme.colorScheme.surfaceContainerHighest,
            arc: theme.colorScheme.primary,
            overrun: theme.colorScheme.tertiary,
            strokeWidth: 12 * scale,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24 * scale),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.arc,
    required this.overrun,
    required this.strokeWidth,
  });

  /// How far through the usual cycle length today is. May exceed 1.
  final double? progress;
  final Color track;
  final Color arc;

  /// Used for the part of the ring beyond the usual length.
  final Color overrun;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(centre, radius, trackPaint);

    final fraction = progress;
    if (fraction == null || fraction <= 0) return;

    final circle = Rect.fromCircle(center: centre, radius: radius);
    const top = -math.pi / 2;

    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Up to the usual length.
    canvas.drawArc(
      circle,
      top,
      2 * math.pi * math.min(fraction, 1),
      false,
      stroke(arc),
    );

    if (fraction <= 1) return;

    // Beyond it, drawn as a second lap in a different colour so being late
    // reads differently from being on time. The day number in the middle
    // carries the same fact in words, so this is never colour alone.
    canvas.drawArc(
      circle,
      top,
      2 * math.pi * math.min(fraction - 1, 1),
      false,
      stroke(overrun),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.arc != arc ||
      old.overrun != overrun ||
      old.strokeWidth != strokeWidth;
}
