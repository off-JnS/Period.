import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/logic/pregnancy_week.dart';
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
    final scheme = theme.colorScheme;
    final currentDay = day;

    final spoken = currentDay == null
        ? l10n.noCycleInProgress
        : l10n.cycleDayAccessibility(currentDay);

    // Grow with the user's text size rather than clipping. Capped so that a very
    // large setting does not push everything else off the screen.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final diameter = 232.0 * scale;

    final length = expectedLength;
    // Deliberately NOT clamped to 1. Past the usual length the ring would
    // otherwise look identical to a cycle finishing exactly on time, and "am I
    // late" is the most common reason to open this screen at all.
    final progress = currentDay == null || length == null || length <= 0
        ? null
        : currentDay / length;

    final Widget centre = currentDay == null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.water_drop_outlined, size: 28, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                l10n.noCycleInProgress,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.cycleDayCaption,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                '$currentDay',
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge?.copyWith(
                  // Tabular so the number does not shift as the day changes.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (length != null && length > 0)
                Text(
                  l10n.usualLengthCaption(length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          );

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _RingPainter(
            progress: progress,
            track: scheme.surfaceContainerHighest,
            glow: scheme.primaryContainer,
            arcStart: Color.lerp(scheme.primary, scheme.surface, 0.55)!,
            arc: scheme.primary,
            overrun: scheme.onPrimaryContainer,
            knob: scheme.surfaceContainerLowest,
            strokeWidth: 14 * scale,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(30 * scale),
              // Scales the text down rather than clipping it when a long
              // German caption meets a large text setting.
              child: FittedBox(fit: BoxFit.scaleDown, child: centre),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Today ring in pregnancy mode: weeks plus days since the last period,
/// in the conventional 12+3 form (docs/cycle-logic.md §6).
///
/// The arc fills towards 40 weeks as decoration only, as with the cycle ring:
/// the numbers in the middle carry the meaning, and no due date is shown.
class PregnancyWeekRing extends StatelessWidget {
  /// Creates the ring.
  const PregnancyWeekRing({required this.week, super.key});

  /// How far along.
  final PregnancyWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final diameter = 232.0 * scale;

    return Semantics(
      label: l10n.pregnancyAccessibility(week.weeks, week.days),
      excludeSemantics: true,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _RingPainter(
            progress: week.totalDays / (40 * 7),
            track: scheme.surfaceContainerHighest,
            glow: scheme.primaryContainer,
            arcStart: Color.lerp(scheme.primary, scheme.surface, 0.55)!,
            arc: scheme.primary,
            overrun: scheme.onPrimaryContainer,
            knob: scheme.surfaceContainerLowest,
            strokeWidth: 14 * scale,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(30 * scale),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.pregnancyCaption,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      l10n.pregnancyWeeksAndDays(week.weeks, week.days),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      l10n.pregnancyWeeksDaysUnit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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
    required this.glow,
    required this.arcStart,
    required this.arc,
    required this.overrun,
    required this.knob,
    required this.strokeWidth,
  });

  /// How far through the usual cycle length today is. May exceed 1.
  final double? progress;
  final Color track;

  /// The soft wash inside the ring.
  final Color glow;

  /// The arc fades in from this colour to [arc].
  final Color arcStart;
  final Color arc;

  /// Used for the part of the ring beyond the usual length.
  final Color overrun;

  /// The dot marking today at the end of the arc.
  final Color knob;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    // A faint wash inside the ring gives the number something to sit on.
    canvas.drawCircle(
      centre,
      radius - strokeWidth / 2,
      Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: 0.6), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final fraction = progress;
    if (fraction == null || fraction <= 0) return;

    final circle = Rect.fromCircle(center: centre, radius: radius);
    const top = -math.pi / 2;
    // The round cap reaches back past twelve o'clock. Starting the gradient
    // that far back keeps the cap in the start colour instead of wrapping round
    // to the end colour and leaving a dark seam at the top.
    final cap = strokeWidth / 2 / radius;
    final rotation = GradientRotation(top - cap);

    void lap(double sweep, Color from, Color to) => canvas.drawArc(
      circle,
      top,
      2 * math.pi * sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: [from, to],
          endAngle: 2 * math.pi * math.max(sweep, 0.01) + cap,
          transform: rotation,
        ).createShader(circle)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Up to the usual length.
    final firstLap = math.min(fraction, 1.0);
    lap(firstLap, arcStart, arc);

    // Beyond it, drawn as a second lap in a different colour so being late
    // reads differently from being on time. The day number in the middle
    // carries the same fact in words, so this is never colour alone.
    final secondLap = math.min(fraction - 1, 1.0);
    if (secondLap > 0) lap(secondLap, arc, overrun);

    // A knob where today sits, so the end of the arc reads as a position.
    final end = top + 2 * math.pi * (secondLap > 0 ? secondLap : firstLap);
    canvas.drawCircle(
      centre + Offset(math.cos(end), math.sin(end)) * radius,
      strokeWidth * 0.28,
      Paint()..color = knob,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.glow != glow ||
      old.arcStart != arcStart ||
      old.arc != arc ||
      old.overrun != overrun ||
      old.knob != knob ||
      old.strokeWidth != strokeWidth;
}
