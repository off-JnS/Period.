import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'app_lock.dart';

/// Covers the whole app, sheets and dialogs included, while [lock] is locked.
///
/// Sits above the navigator, so nothing pushed on top of a screen can show
/// through. The app underneath stays built -- her half-typed note survives a
/// lock -- but is hidden from sight, from touch and from the screen reader.
class LockGate extends StatefulWidget {
  /// Creates the gate.
  const LockGate({required this.lock, required this.child, super.key});

  /// The lock state to follow.
  final AppLock lock;

  /// The app.
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // Hidden, not merely inactive: the Face ID prompt and Control Center
      // make the app inactive too, and locking then would re-lock it while
      // she is unlocking it.
      onHide: widget.lock.appHidden,
      // Back on screen: ask straight away rather than making her tap first.
      onShow: _promptIfLocked,
    );
    // A cold start with the lock on asks at once, too.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptIfLocked());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _promptIfLocked() {
    if (!mounted || !widget.lock.locked) return;
    widget.lock.unlock(reason: AppLocalizations.of(context).appLockReason);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.lock,
      builder: (context, child) {
        final locked = widget.lock.locked;
        return Stack(
          children: [
            ExcludeSemantics(
              excluding: locked,
              child: AbsorbPointer(absorbing: locked, child: child),
            ),
            if (locked)
              Positioned.fill(
                child: _LockScreen(
                  busy: widget.lock.authenticating,
                  onUnlock: _promptIfLocked,
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// What shows while locked: nothing of hers, just a way back in.
class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.busy, required this.onUnlock});

  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      // Opaque, not a blur: behind it is the app with her data in it.
      color: scheme.groupedBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 40,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.lockedTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  // Disabled while the system prompt is up, so a second tap
                  // cannot stack another prompt behind it.
                  onPressed: busy
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onUnlock();
                        },
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(l10n.unlock),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
