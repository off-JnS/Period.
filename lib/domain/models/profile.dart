import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';

/// Which contraception she uses, if any. docs/cycle-logic.md §10.
///
/// Stored by name, so values may be added but never renamed.
enum ContraceptionMethod {
  /// Nothing.
  none(hormonal: false),

  /// Condoms, or another barrier method.
  condom(hormonal: false),

  /// The combined pill.
  combinedPill(hormonal: true),

  /// The progestin-only pill.
  progestinPill(hormonal: true),

  /// A hormonal IUD.
  hormonalIud(hormonal: true),

  /// A copper IUD. Not hormonal: the cycle stays natural.
  copperIud(hormonal: false),

  /// An implant.
  implant(hormonal: true),

  /// A vaginal ring.
  ring(hormonal: true),

  /// A patch.
  patch(hormonal: true),

  /// An injection.
  injection(hormonal: true),

  /// Something not listed. Not assumed to be hormonal.
  other(hormonal: false);

  const ContraceptionMethod({required this.hormonal});

  /// Whether the method acts through hormones, so bleeding follows the
  /// regimen rather than a natural cycle.
  final bool hormonal;
}

/// A condition she has already been diagnosed with. docs/cycle-logic.md §10:
/// recorded only, never suggested or inferred.
///
/// Stored by name, so values may be added but never renamed.
enum KnownCondition {
  /// Polycystic ovary syndrome.
  pcos,

  /// Endometriosis.
  endometriosis,

  /// Adenomyosis.
  adenomyosis,

  /// Uterine fibroids.
  fibroids,

  /// A thyroid condition.
  thyroid,

  /// Premenstrual dysphoric disorder.
  pmdd,
}

/// What she has told the app about herself. Every field is optional.
///
/// None of it is an input to any estimate (docs/cycle-logic.md §10); it is
/// shown back to her and in the doctor report, and that is all.
@freezed
abstract class Profile with _$Profile {
  const Profile._();

  const factory Profile({
    /// The year she was born. Never a full birth date.
    int? birthYear,

    /// The cycle length she believes is usual for her, in days.
    int? usualCycleLength,

    /// The period length she believes is usual for her, in days.
    int? usualPeriodLength,

    /// Her contraception method, or null if she has not said.
    ContraceptionMethod? contraception,

    /// Conditions she has been diagnosed with.
    @Default(<KnownCondition>{}) Set<KnownCondition> conditions,
  }) = _Profile;

  /// The shortest usual cycle length accepted.
  static const minCycleLength = 15;

  /// The longest usual cycle length accepted.
  static const maxCycleLength = 90;

  /// The shortest usual period length accepted.
  static const minPeriodLength = 1;

  /// The longest usual period length accepted.
  static const maxPeriodLength = 14;

  /// The youngest age a birth year may give, counted in calendar years.
  static const minAge = 8;

  /// The oldest age a birth year may give, counted in calendar years.
  static const maxAge = 70;

  /// Whether she has told the app nothing at all.
  bool get isEmpty =>
      birthYear == null &&
      usualCycleLength == null &&
      usualPeriodLength == null &&
      contraception == null &&
      conditions.isEmpty;
}
