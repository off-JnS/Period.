import 'package:local_auth/local_auth.dart';

/// Asks the device to confirm it is her.
///
/// An interface for the same reason [DatabaseKeyStore] and [BackupTransfer] are
/// ones: this is the only part of the lock that reaches a platform plugin, so
/// keeping it behind a seam means the gate's behaviour -- when it locks, when it
/// does not, and what happens when authentication is impossible -- is all
/// testable without a device.
abstract class AppLock {
  /// Whether this device can authenticate at all.
  ///
  /// False when there is no biometric enrolled *and* no device passcode set.
  /// The gate treats that as "let her in", never as "keep her out"; see
  /// [LockGate].
  Future<bool> isAvailable();

  /// Prompts, returning whether she authenticated.
  Future<bool> authenticate(String reason);
}

/// The real lock: whatever the operating system already uses.
class DeviceAppLock implements AppLock {
  /// Creates the lock.
  DeviceAppLock({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      // A platform that cannot answer is one that cannot authenticate, and the
      // answer to that is the same as a plain "no": open the app.
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Deliberately not biometric-only. Section 9 asks for a PIN *or*
        // biometric lock, and refusing the device passcode would shut out
        // anyone whose fingerprint is not enrolled or not working today.
        biometricOnly: false,
        // The prompt itself backgrounds the app on iOS. This keeps the request
        // alive across that rather than cancelling it.
        persistAcrossBackgrounding: true,
      );
    } on Object {
      // A refusal and a failure are the same to the caller: not authenticated,
      // still locked, free to try again.
      return false;
    }
  }
}
