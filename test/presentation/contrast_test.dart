import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every text colour the screens actually use, on every surface it sits on,
/// held to WCAG AA in both themes: 4.5:1 for text, 3:1 for large text and
/// meaningful graphics. A theme tweak that quietly drops a pair below the floor
/// fails here instead of on someone's phone.
void main() {
  for (final (name, theme) in [
    ('light', lightTheme()),
    ('dark', darkTheme()),
  ]) {
    final s = theme.colorScheme;
    final pairs = <(String, Color, Color, double)>[
      ('body text on card', s.onSurface, s.groupedCard, 4.5),
      ('body text on page', s.onSurface, s.groupedBackground, 4.5),
      ('footnotes on page', s.onSurfaceVariant, s.groupedBackground, 4.5),
      ('secondary text on card', s.onSurfaceVariant, s.groupedCard, 4.5),
      ('tinted headings on card', s.primary, s.groupedCard, 4.5),
      ('tinted month label on page', s.primary, s.groupedBackground, 4.5),
      ('button label on button', s.onPrimary, s.primary, 4.5),
      ('selected chip label', s.onPrimary, s.primary, 4.5),
      ('unselected chip label', s.onSurface, s.groupedBackground, 4.5),
      ('period-start day number', s.onPrimary, s.primary, 4.5),
      (
        'estimated day number',
        s.onSurface,
        Color.alphaBlend(
          s.tertiaryContainer.withValues(alpha: 0.7),
          s.groupedCard,
        ),
        4.5,
      ),
      ('in-progress pill', s.onPrimaryContainer, s.primaryContainer, 4.5),
      (
        'inactive tab label',
        s.onSurfaceVariant.withValues(alpha: 0.8),
        s.groupedCard,
        4.5,
      ),
      ('ring arc on page', s.primary, s.groupedBackground, 3),
      ('chart bar on card', s.primary, s.groupedCard, 3),
      ('estimate dashes on card', s.tertiary, s.groupedCard, 3),
      ('today ring on card', s.primary, s.groupedCard, 3),
    ];
    group('$name theme', () {
      for (final (label, fg, bg, floor) in pairs) {
        test(label, () {
          final ratio = contrast(Color.alphaBlend(fg, bg), bg);
          expect(ratio, greaterThanOrEqualTo(floor), reason: '$label: $ratio');
        });
      }
    });
  }
}
