import 'package:flutter/services.dart';

/// Hands the home-screen widget its snapshot. See WidgetBridge in
/// ios/Runner/AppDelegate.swift.
///
/// An interface so tests need no platform channel, and so the Android build,
/// which has no widget yet, simply does nothing.
abstract interface class WidgetBridge {
  /// Replaces what the widget may show with [json].
  Future<void> update(String json);

  /// Removes it: the widget then shows an empty ring.
  Future<void> clear();
}

/// The real bridge, over a method channel to the iOS app.
class MethodChannelWidgetBridge implements WidgetBridge {
  /// Creates the bridge.
  const MethodChannelWidgetBridge();

  static const _channel = MethodChannel('period/widget');

  @override
  Future<void> update(String json) => _call('update', json);

  @override
  Future<void> clear() => _call('clear');

  Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } on MissingPluginException {
      // No widget on this platform. Nothing to update.
    }
  }
}
