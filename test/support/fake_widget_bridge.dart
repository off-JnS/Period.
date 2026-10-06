import 'dart:convert';

import 'package:period/data/widget/widget_bridge.dart';

/// Records what the widget would have been given.
class FakeWidgetBridge implements WidgetBridge {
  /// Every snapshot sent, decoded, oldest first.
  final List<Map<String, Object?>> snapshots = [];

  /// How many times it was cleared.
  int cleared = 0;

  @override
  Future<void> update(String json) async =>
      snapshots.add((jsonDecode(json) as Map).cast<String, Object?>());

  @override
  Future<void> clear() async => cleared++;
}
