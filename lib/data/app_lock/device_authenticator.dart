import 'package:local_auth/local_auth.dart';

/// Asks the device to confirm it is the owner: Face ID, Touch ID or the
/// device passcode, whichever the device offers.
///
/// An interface so nothing outside this file depends on `local_auth`, the same
/// arrangement as `DatabaseKeyStore`, and so the lock can be tested without a
/// platform channel.
///
/// The app keeps no PIN of its own. The device passcode is the fallback, as in
/// Notes' locked notes: an app-specific PIN would be one more secret to store,
/// and a four-digit one guarded by nothing stronger than this app.
abstract interface class DeviceAuthenticator {
  /// Whether the device can authenticate its owner at all. False when no
  /// passcode is set, in which case the lock cannot be offered.
  Future<bool> canAuthenticate();

  /// Shows the system prompt. True only for a confirmed owner; cancelling,
  /// failing and any platform error are all false. Never throws.
  Future<bool> authenticate({required String reason});
}

/// The real thing, over `local_auth`.
class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  /// Creates the authenticator.
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Face ID or Touch ID first, the device passcode when those fail or
        // are not set up: locking her out of her own data because a finger
        // was wet is the wrong failure.
        biometricOnly: false,
      );
    } on Object {
      // Cancelled, locked out, no credentials: all mean "still locked". The
      // lock screen stays up with its button, so she can simply try again.
      return false;
    }
  }
}
