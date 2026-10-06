import 'package:flutter/material.dart';

/// A card in the style of the Health app's summary tiles.
///
/// The category sits at the top in the tint colour with its icon, the content
/// below it in the label colour. The icon and heading together tell one card
/// from another; section 9 rules out colour alone, so the tint only agrees
/// with them.
class SectionCard extends StatelessWidget {
  /// Creates the card.
  const SectionCard({
    required this.heading,
    required this.child,
    this.icon,
    this.trailing,
    this.color,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
    super.key,
  });

  /// The category label at the top.
  final String heading;

  /// The body.
  final Widget child;

  /// Shown before the heading, when given.
  final IconData? icon;

  /// Placed at the end of the heading row, when given.
  final Widget? trailing;

  /// Overrides the card colour.
  final Color? color;

  /// Overrides the tint of the icon and heading.
  final Color? accent;

  /// Space inside the card.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accent ?? theme.colorScheme.primary;

    return Card(
      color: color,
      // Not one merged node: a button in the heading row, like Edit or the
      // doctor hint, has to be reachable and pressable on its own.
      semanticContainer: false,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon case final glyph?) ...[
                  ExcludeSemantics(child: Icon(glyph, size: 18, color: tint)),
                  const SizedBox(width: 6),
                ],
                // Expanded so a longer German heading wraps instead of
                // overflowing.
                Expanded(
                  // A heading to VoiceOver too, so its rotor can jump from
                  // card to card the way it jumps between sections in Health.
                  child: Semantics(
                    header: true,
                    child: Text(
                      heading,
                      style: theme.textTheme.titleSmall?.copyWith(color: tint),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
