import 'package:freezed_annotation/freezed_annotation.dart';

part 'cycle_mode.freezed.dart';

/// What kind of cycle, if any, the user currently has.
///
/// CLAUDE.md section 10 requires "predictions are off" to be a first-class
/// state rather than a special case bolted on later. That is what this type is
/// for: prediction code takes the settings and returns an explicit
/// "disabled, because —" result, so no caller can forget the case.
enum CycleMode {
  /// A natural cycle. Predictions apply.
  natural,

  /// Hormonal contraception.
  ///
  /// A withdrawal bleed is scheduled by the regimen rather than by a cycle, so
  /// predicting it from cycle history is meaningless. Continuous regimens may
  /// produce no bleed at all, which is not missing data.
  hormonalContraception,

  /// Pregnancy. Cycle statistics are hidden rather than zeroed.
  pregnancy,

  /// Perimenopause.
  ///
  /// STRAW+10 defines the transition *by* rising cycle variability, so a
  /// confident prediction is most wrong exactly where it would be most trusted.
  /// Predictions are off by default here but the user may turn them back on.
  perimenopause,
}

/// The user's cycle mode and the choices that go with it.
@freezed
abstract class CycleSettings with _$CycleSettings {
  const CycleSettings._();

  const factory CycleSettings({
    /// The mode the user selected.
    @Default(CycleMode.natural) CycleMode mode,

    /// Whether the user asked for predictions despite being in a mode that
    /// disables them. Only [CycleMode.perimenopause] honours this; see
    /// [predictionsEnabled].
    @Default(false) bool predictionsOptedIn,
  }) = _CycleSettings;

  /// Whether any prediction may be computed at all.
  ///
  /// Contraception and pregnancy are absolute: there is no natural cycle to
  /// predict from, so opting in would not make a prediction meaningful, only
  /// confident. Perimenopause is the user's call.
  bool get predictionsEnabled => switch (mode) {
    CycleMode.natural => true,
    CycleMode.perimenopause => predictionsOptedIn,
    CycleMode.hormonalContraception || CycleMode.pregnancy => false,
  };
}
