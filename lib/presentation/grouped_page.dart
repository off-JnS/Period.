import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// An iOS screen: a collapsing large title over an inset grouped page.
///
/// The navigation bar is the system one, so it collapses into the small
/// centred title on scroll and blurs what passes under it, exactly as in
/// Settings or Health.
class GroupedPage extends StatelessWidget {
  /// Creates the page.
  const GroupedPage({
    required this.title,
    required this.children,
    this.trailing,
    this.backLabel,
    this.bottomPadding = 32,
    super.key,
  });

  /// The large title.
  final String title;

  /// The content, laid out top to bottom with the page's side margins.
  final List<Widget> children;

  /// Controls at the end of the navigation bar.
  final Widget? trailing;

  /// The previous screen's title, for a back button, when this screen was
  /// pushed. Null on a root screen, which has no way back.
  final String? backLabel;

  /// Space after the last child, so nothing ends flush against the tab bar.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.groupedBackground,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(title),
            trailing: trailing,
            backgroundColor: scheme.groupedBackground.withValues(alpha: 0.85),
            // No hairline until content scrolls under, as iOS does.
            border: null,
            automaticallyImplyLeading: backLabel != null,
            previousPageTitle: backLabel,
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
              sliver: SliverList.list(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small grey heading above a group, as in Settings.
class GroupHeader extends StatelessWidget {
  /// Creates the header.
  const GroupHeader(this.text, {super.key});

  /// The heading.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A small grey explanation under a group, as in Settings.
class GroupFooter extends StatelessWidget {
  /// Creates the footer.
  const GroupFooter(this.text, {super.key});

  /// The explanation.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
