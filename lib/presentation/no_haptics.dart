import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's binding: Flutter's own, except that no vibration ever reaches
/// the phone.
///
/// The owner decided on 2026-09-28 that the app has no haptic feedback at
/// all. Removing the app's own calls is not enough, because the framework's
/// iOS controls vibrate by themselves (a switch as it flips, a picker wheel
/// as it turns, a dialog button under the finger) and offer no setting to
/// stop it. Every one of them goes through the same platform message, so
/// dropping that message here silences all of them, including any added
/// later.
class NoHapticsBinding extends WidgetsFlutterBinding {
  NoHapticsBinding._();

  static bool _created = false;

  /// Installs the binding. Call first thing in `main`, in place of
  /// `WidgetsFlutterBinding.ensureInitialized`.
  static WidgetsBinding ensureInitialized() {
    if (!_created) {
      _created = true;
      NoHapticsBinding._();
    }
    return WidgetsBinding.instance;
  }

  @override
  BinaryMessenger createBinaryMessenger() =>
      HapticsDroppingMessenger(super.createBinaryMessenger());
}

/// Passes every platform message through to [inner] except requests to
/// vibrate, which it answers itself as done.
class HapticsDroppingMessenger implements BinaryMessenger {
  /// Wraps [inner].
  const HapticsDroppingMessenger(this.inner);

  /// Where everything else goes.
  final BinaryMessenger inner;

  static const _codec = JSONMethodCodec();

  /// Whether [message] on [channel] asks the phone to vibrate.
  static bool isHaptic(String channel, ByteData? message) {
    if (channel != SystemChannels.platform.name || message == null) {
      return false;
    }
    try {
      return _codec
          .decodeMethodCall(message)
          .method
          .startsWith('HapticFeedback.');
    } on Object {
      return false;
    }
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (isHaptic(channel, message)) {
      // A success reply, so the caller's future completes normally rather
      // than failing as if the platform had no such method.
      return Future.value(_codec.encodeSuccessEnvelope(null));
    }
    return inner.send(channel, message);
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      inner.handlePlatformMessage(channel, data, callback);

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      inner.setMessageHandler(channel, handler);
}
