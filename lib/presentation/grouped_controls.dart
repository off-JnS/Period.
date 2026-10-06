import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'grouped_page.dart';

/// A checkmark list, as iOS uses for picking one option from a few.
///
/// Rows wrap rather than truncate, so it holds up at large text sizes and in
/// German where a segmented control would not.
class CheckList<T> extends StatelessWidget {
  /// Creates the list.
  const CheckList({
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.icon,
    super.key,
  });

  /// Every option, in display order.
  final List<T> options;

  /// The checked option.
  final T? selected;

  /// The display name of an option.
  final String Function(T option) label;

  /// Called with the option tapped. For a single choice, tapping the
  /// current option does nothing.
  final ValueChanged<T> onSelected;

  /// An icon before each option's name, when given.
  final IconData Function(T option)? icon;

  @override
  Widget build(BuildContext context) => _CheckCard<T>(
    options: options,
    isChecked: (option) => option == selected,
    label: label,
    icon: icon,
    onTap: (option) => option == selected ? null : () => onSelected(option),
    exclusive: true,
  );
}

/// A checkmark list where any number of options may be checked, each tap
/// toggling one.
class MultiCheckList<T> extends StatelessWidget {
  /// Creates the list.
  const MultiCheckList({
    required this.options,
    required this.selected,
    required this.label,
    required this.onToggled,
    this.icon,
    super.key,
  });

  /// Every option, in display order.
  final List<T> options;

  /// The checked options.
  final Set<T> selected;

  /// The display name of an option.
  final String Function(T option) label;

  /// Called with the option tapped, checked or not.
  final ValueChanged<T> onToggled;

  /// An icon before each option's name, when given.
  final IconData Function(T option)? icon;

  @override
  Widget build(BuildContext context) => _CheckCard<T>(
    options: options,
    isChecked: selected.contains,
    label: label,
    icon: icon,
    onTap: (option) =>
        () => onToggled(option),
    exclusive: false,
  );
}

class _CheckCard<T> extends StatelessWidget {
  const _CheckCard({
    required this.options,
    required this.isChecked,
    required this.label,
    required this.onTap,
    required this.exclusive,
    this.icon,
  });

  final List<T> options;
  final bool Function(T option) isChecked;
  final String Function(T option) label;
  final VoidCallback? Function(T option) onTap;
  final bool exclusive;
  final IconData Function(T option)? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) Divider(indent: icon == null ? 16 : 52),
            Semantics(
              selected: exclusive ? isChecked(option) : null,
              checked: exclusive ? null : isChecked(option),
              inMutuallyExclusiveGroup: exclusive,
              button: true,
              excludeSemantics: true,
              label: label(option),
              child: InkWell(
                onTap: onTap(option),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                    child: Row(
                      children: [
                        if (icon case final glyph?) ...[
                          RowIcon(glyph(option)),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            label(option),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        // The checkmark is a shape as well as a colour, so the
                        // selection never rests on colour alone.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: isChecked(option)
                              ? Icon(
                                  Icons.check_rounded,
                                  key: const ValueKey(true),
                                  size: 22,
                                  color: theme.colorScheme.primary,
                                )
                              : const SizedBox(key: ValueKey(false), width: 22),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single switch in its own card, with an explanation beneath.
class SwitchGroup extends StatelessWidget {
  /// Creates the group.
  const SwitchGroup({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.footer,
    super.key,
  });

  /// The switch's label.
  final String title;

  /// Whether it is on.
  final bool value;

  /// Called when she flips it.
  final ValueChanged<bool> onChanged;

  /// The explanation under the card.
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: value,
            onChanged: onChanged,
            title: Text(title),
          ),
        ),
        GroupFooter(footer),
      ],
    );
  }
}

/// A row that shows a value and opens something to change it, as a Settings
/// row with a chevron does.
class ValueRow extends StatelessWidget {
  /// Creates the row.
  const ValueRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
    super.key,
  });

  /// Shown before the label.
  final IconData icon;

  /// What the row is.
  final String label;

  /// What is chosen, or a "not set" text.
  final String value;

  /// Whether [value] is the "not set" text, shown fainter.
  final bool placeholder;

  /// Opens the picker.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final valueText = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        value,
        key: ValueKey(value),
        style: theme.textTheme.bodyLarge?.copyWith(
          color: placeholder
              ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
              : scheme.onSurfaceVariant,
        ),
      ),
    );
    final labelText = Text(label, style: theme.textTheme.bodyLarge);
    // At large text sizes the value goes under the label, as iOS does,
    // instead of both squeezing until words break mid-word.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.4;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
            child: Row(
              children: [
                RowIcon(icon),
                const SizedBox(width: 12),
                if (stacked)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [labelText, valueText],
                    ),
                  )
                else ...[
                  Expanded(flex: 3, child: labelText),
                  const SizedBox(width: 8),
                  // Flexible, so a long German value wraps in its own column
                  // instead of pushing the label off the row.
                  Flexible(
                    flex: 2,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: valueText,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small tinted square behind a row's icon, as iOS Settings draws them.
class RowIcon extends StatelessWidget {
  /// Creates the icon.
  const RowIcon(this.icon, {super.key});

  /// The glyph.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 17, color: scheme.primary),
      ),
    );
  }
}
