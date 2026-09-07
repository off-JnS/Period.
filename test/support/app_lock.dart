import 'package:period/data/app_lock.dart';

/// An [AppLock] that answers however a test needs it to.
class FakeAppLock implements AppLock {
  /// Creates a lock that is available and accepts, unless told otherwise.
  FakeAppLock({this.available = true, this.accepts = true});

  /// What [isAvailable] reports. False models a phone with no biometric
  /// enrolled and no passcode set.
  bool available;

  /// Whether [authenticate] succeeds.
  bool accepts;

  /// How many times the device was asked.
  int prompts = 0;

  /// The reason shown in the last prompt, so a test can check it says nothing
  /// about cycles.
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    lastReason = reason;
    return accepts;
  }
}
