import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'lock_screen.dart';

/// Stands in front of the app when section 9's optional lock is on.
///
/// Two things here are easy to get wrong, and both are worse than having no
/// lock at all.
///
/// **It never locks her out.** If the device has no biometric enrolled and no
/// passcode set, authentication cannot succeed, and a gate that waited for it
/// would leave her permanently unable to open her own health data -- the
/// failure section 1 ranks alongside a leak. When the device cannot
/// authenticate, the app opens.
///
/// **The prompt backgrounds the app.** On iOS the system sheet drives the app
/// to inactive and then paused, so a naive "re-lock when it leaves the
/// foreground" re-locks during its own prompt and loops forever.
/// [_authenticating] is what stops that.
///
/// While locked it *replaces* the app rather than covering it. A lock screen
/// stacked on top would leave the real content built, in the tree, and one
/// stray hit test away from being readable.
class LockGate extends ConsumerStatefulWidget {
  /// Creates the gate.
  const LockGate({required this.child, super.key});

  /// The app, shown once she is through.
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  /// Starts locked, and is lowered only by a decision made below.
  ///
  /// The safe direction: a build that somehow never resolves the setting shows
  /// the lock screen rather than her entries.
  bool _locked = true;

  /// True while the device's own prompt is up.
  ///
  /// The prompt takes the app out of the foreground, so without this the
  /// lifecycle handler would re-lock in the middle of unlocking.
  bool _authenticating = false;

  /// Whether the stored setting has been read yet.
  bool _decided = false;

  /// The setting, once read. Kept here because the lifecycle callback is
  /// synchronous and must not wait on a database read to know whether this app
  /// locks at all.
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || _authenticating) return;

    switch (state) {
      // Locked the moment it leaves the foreground, not when it comes back: by
      // the time it resumes, a frame of the real content has already been
      // rendered and possibly seen.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (!_locked) setState(() => _locked = true);
      case AppLifecycleState.resumed:
        if (_locked) unawaited(_authenticate());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Reads the setting and, if the lock is on, asks the device.
  Future<void> _open() async {
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;

    setState(() {
      _decided = true;
      _enabled = settings.appLockEnabled;
      if (!_enabled) _locked = false;
    });

    if (_enabled) await _authenticate();
  }

  Future<void> _authenticate() async {
    final lock = ref.read(appLockProvider);
    final reason = AppLocalizations.of(context).unlockReason;

    setState(() => _authenticating = true);
    try {
      // Asked first, and honoured. A device with nothing to authenticate
      // against would refuse every prompt, and treating that as "stay locked"
      // would be indistinguishable from losing her data.
      if (!await lock.isAvailable()) {
        if (mounted) setState(() => _locked = false);
        return;
      }

      final unlocked = await lock.authenticate(reason);
      if (mounted) setState(() => _locked = !unlocked);
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Locked until proven otherwise, including before the setting has been
    // read. The child is not built at all in that state.
    if (!_decided || _locked) {
      return LockScreen(onUnlock: _authenticating ? null : _authenticate);
    }
    return widget.child;
  }
}
