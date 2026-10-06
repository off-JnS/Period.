import 'dart:async';

import 'package:period/data/app_lock/device_authenticator.dart';

/// A device that answers the lock's questions as the test tells it to.
class FakeAuthenticator implements DeviceAuthenticator {
  /// Whether the device has a passcode set.
  bool available = true;

  /// Whether the next prompt is passed.
  bool succeeds = true;

  /// How many system prompts have been shown.
  int prompts = 0;

  /// When set, prompts wait on this instead of answering at once.
  Completer<bool>? pending;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<bool> authenticate({required String reason}) {
    prompts++;
    return pending?.future ?? Future.value(succeeds);
  }
}
