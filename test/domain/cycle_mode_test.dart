import 'package:period/domain/models/cycle_mode.dart';
import 'package:test/test.dart';

void main() {
  group('predictionsEnabled', () {
    test('a natural cycle predicts', () {
      expect(const CycleSettings().predictionsEnabled, isTrue);
      expect(
        const CycleSettings(mode: CycleMode.natural).predictionsEnabled,
        isTrue,
      );
    });

    test('contraception and pregnancy never predict, opted in or not', () {
      // There is no natural cycle to predict from, so opting in would not make a
      // prediction meaningful -- only confident.
      for (final mode in [
        CycleMode.hormonalContraception,
        CycleMode.pregnancy,
      ]) {
        expect(CycleSettings(mode: mode).predictionsEnabled, isFalse);
        expect(
          CycleSettings(
            mode: mode,
            predictionsOptedIn: true,
          ).predictionsEnabled,
          isFalse,
          reason: '$mode must stay off even when opted in',
        );
      }
    });

    test('perimenopause is off by default and the user may turn it on', () {
      // STRAW+10 defines the transition by rising variability, so a confident
      // prediction is most wrong exactly where it would be most trusted --
      // but it is her call, not ours.
      expect(
        const CycleSettings(mode: CycleMode.perimenopause).predictionsEnabled,
        isFalse,
      );
      expect(
        const CycleSettings(
          mode: CycleMode.perimenopause,
          predictionsOptedIn: true,
        ).predictionsEnabled,
        isTrue,
      );
    });

    test('every mode is accounted for', () {
      // The switch is exhaustive; this fails to compile rather than silently
      // defaulting if a mode is added without deciding what it does.
      for (final mode in CycleMode.values) {
        expect(
          () => CycleSettings(mode: mode).predictionsEnabled,
          returnsNormally,
        );
      }
    });
  });

  test('defaults to a natural cycle with predictions on', () {
    const settings = CycleSettings();
    expect(settings.mode, CycleMode.natural);
    expect(settings.predictionsOptedIn, isFalse);
    expect(settings.predictionsEnabled, isTrue);
  });
}
