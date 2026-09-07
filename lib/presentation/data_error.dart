import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Shown when the app cannot read the user's data.
///
/// Never the raw exception. A user who cannot open her cycle data needs to know
/// what happened and what to do, not a stack trace -- and section 8 puts every
/// user-facing string in the ARB files, which a formatted error object can never
/// be. Shared by every screen that reads, so the one screen nobody remembered to
/// check cannot be the one that leaks `SqliteException(26)` onto the display.
class DataErrorPanel extends StatelessWidget {
  /// Creates the panel.
  const DataErrorPanel({required this.onRetry, super.key});

  /// Re-reads whatever failed.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.couldNotOpenData,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.couldNotOpenDataDetail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
          ],
        ),
      ),
    );
  }
}
