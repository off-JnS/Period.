import 'package:flutter/foundation.dart';

import '../../data/app_lock/device_authenticator.dart';

/// What happened when the user tried to turn the lock on or off.
enum LockChange {
  /// Done and stored.
  changed,

  /// She cancelled or failed the confirmation; nothing changed.
  notConfirmed,

  /// The device has no passcode, so there is nothing to lock with.
  unavailable,
}

/// Whether the app is locked, and the rules for when it locks.
///
/// Section 9: optional, enforced on cold start and on resume. It locks when
/// the app leaves the screen -- not merely when it loses focus, which also
/// happens for Control Center and for the Face ID prompt itself, and would
/// otherwise re-lock the app in the middle of unlocking it.
class AppLock extends ChangeNotifier {
  /// Creates the lock. Starts locked when [enabled], so a cold start asks.
  AppLock({
    required this._authenticator,
    required bool enabled,
    required this._save,
  }) : _enabled = enabled,
       _locked = enabled;

  final DeviceAuthenticator _authenticator;
  final Future<void> Function({required bool enabled}) _save;

  bool _enabled;
  bool _locked;
  bool _authenticating = false;

  /// Whether she turned the lock on.
  bool get enabled => _enabled;

  /// Whether the app is covered right now.
  bool get locked => _locked;

  /// Whether a system prompt is showing, so a second one is not stacked on it.
  bool get authenticating => _authenticating;

  /// The app left the screen: lock it, if the lock is on.
  void appHidden() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// Asks the device to confirm the owner, and unlocks if it does.
  Future<void> unlock({required String reason}) async {
    if (!_locked || _authenticating) return;
    if (await _confirm(reason)) {
      _locked = false;
      notifyListeners();
    }
  }

  /// Turns the lock on or off, confirming the owner first either way.
  ///
  /// Turning it on is confirmed so she cannot lock herself out with a
  /// passcode she has not got; turning it off, so someone handed an unlocked
  /// phone cannot quietly remove it.
  Future<LockChange> setEnabled({
    required bool enabled,
    required String reason,
  }) async {
    if (enabled == _enabled) return LockChange.changed;
    if (enabled && !await _authenticator.canAuthenticate()) {
      return LockChange.unavailable;
    }
    if (!await _confirm(reason)) return LockChange.notConfirmed;

    await _save(enabled: enabled);
    _enabled = enabled;
    // Never leave the app locked with the lock switched off.
    if (!enabled) _locked = false;
    notifyListeners();
    return LockChange.changed;
  }

  Future<bool> _confirm(String reason) async {
    if (_authenticating) return false;
    _authenticating = true;
    notifyListeners();
    try {
      return await _authenticator.authenticate(reason: reason);
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }
}
