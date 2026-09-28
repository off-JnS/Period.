import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/no_haptics.dart';

/// Records what reaches the platform.
class _RecordingMessenger implements BinaryMessenger {
  final sent = <String>[];

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    sent.add(
      channel == SystemChannels.platform.name && message != null
          ? const JSONMethodCodec().decodeMethodCall(message).method
          : channel,
    );
    return Future.value(
      channel == SystemChannels.platform.name
          ? const JSONMethodCodec().encodeSuccessEnvelope(null)
          : const StandardMethodCodec().encodeSuccessEnvelope(null),
    );
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}
}

void main() {
  late _RecordingMessenger platform;
  late MethodChannel channel;

  setUp(() {
    platform = _RecordingMessenger();
    channel = MethodChannel(
      SystemChannels.platform.name,
      const JSONMethodCodec(),
      HapticsDroppingMessenger(platform),
    );
  });

  test('every kind of vibration is dropped, and still completes', () async {
    for (final type in [
      null,
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.selectionClick',
    ]) {
      await channel.invokeMethod<void>('HapticFeedback.vibrate', type);
    }
    expect(platform.sent, isEmpty);
  });

  test('everything else on the platform channel still gets through', () async {
    await channel.invokeMethod<void>(
      'SystemSound.play',
      'SystemSoundType.click',
    );
    await channel.invokeMethod<void>('Clipboard.setData', {'text': 'x'});
    expect(platform.sent, ['SystemSound.play', 'Clipboard.setData']);
  });

  test('other channels are never inspected', () async {
    final other = MethodChannel(
      'period/widget',
      const StandardMethodCodec(),
      HapticsDroppingMessenger(platform),
    );
    await other.invokeMethod<void>('HapticFeedback.vibrate');
    expect(platform.sent, ['period/widget']);
  });
}
