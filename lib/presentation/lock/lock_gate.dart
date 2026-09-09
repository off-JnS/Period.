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

  /// Whether the app has actually been in the background since the last
  /// prompt, as opposed to merely losing focus to that prompt.
  bool _wasAway = false;

  /// Whether the stored setting has been read yet.
  bool _decided = false;

  /// The setting as last seen. Mirrored into state because the lifecycle
  /// callback is synchronous and cannot wait on a database read -- but kept in
  /// step by [build] watching the provider, so turning the lock on or off takes
  /// effect immediately rather than on the next launch.
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
        _wasAway = true;
        if (!_locked) setState(() => _locked = true);
      case AppLifecycleState.resumed:
        // Only after the app was genuinely away. The device's own prompt
        // resigns the app active and hands back a `resumed` when it closes, so
        // re-prompting on every resume means a refused prompt immediately
        // raises another one -- a loop with no way out but force-quitting.
        // She reaches the same place with the Unlock button, by choosing to.
        if (!_wasAway) return;
        _wasAway = false;
        if (_locked) unawaited(_authenticate());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Reads the setting and, if the lock is on, asks the device.
  Future<void> _open() async {
    bool enabled;
    try {
      enabled = (await ref.read(settingsProvider.future)).appLockEnabled;
    } on Object {
      // The settings row is unreadable -- a cycle mode from a newer build, or
      // a corrupt value. SettingsDao throws there deliberately, and the screen
      // behind this gate knows how to explain it. Staying locked would mean she
      // could never reach that explanation, or the delete-everything button,
      // and an app that cannot be opened is data that has been erased.
      enabled = false;
    }
    if (!mounted) return;

    setState(() {
      _decided = true;
      _enabled = enabled;
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
    // Watched, not read once: flipping the switch in settings has to reach the
    // gate now rather than on the next launch. A switch that says the app is
    // locked while it is not would be worse than no switch.
    final enabled = ref.watch(settingsProvider).value?.appLockEnabled;
    if (enabled != null && enabled != _enabled) {
      _enabled = enabled;
      // Turning it on does not prompt here -- she is looking at settings, and
      // an unprovoked prompt mid-toggle is jarring. It takes effect the next
      // time the app leaves the foreground, which is when it matters.
      if (!enabled) _locked = false;
    }

    // Locked until proven otherwise, including before the setting has been
    // read. The child is not built at all in that state.
    if (!_decided || _locked) {
      return LockScreen(onUnlock: _authenticating ? null : _authenticate);
    }
    return widget.child;
  }
}
