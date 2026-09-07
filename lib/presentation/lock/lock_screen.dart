import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What is on screen while the app is locked.
///
/// Deliberately says nothing. Section 9 keeps cycle content off a screen that
/// can be read over a shoulder, and this is the screen most likely to be seen
/// by someone who is not her: no cycle day, no estimate, no date.
///
/// A pure widget, like the other screens, so every variant is a golden without
/// a device.
class LockScreen extends StatelessWidget {
  /// Creates the screen.
  const LockScreen({this.onUnlock, super.key});

  /// Asks the device to authenticate again.
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.lockedTitle,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.lockedBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Always offered, never only automatic. A prompt she dismissed
                // by accident would otherwise leave her looking at a locked
                // screen with no way forward.
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.lock_open),
                  label: Text(l10n.unlockAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
