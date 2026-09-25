import '../models/cycle_mode.dart';
import '../models/profile.dart';

/// The age she turns in [currentYear], from her [birthYear].
///
/// docs/cycle-logic.md §10: the year alone determines this exactly, where an
/// age "now" would be one too high for part of every year. Null without a
/// birth year.
int? ageThisYear({required int? birthYear, required int currentYear}) =>
    birthYear == null ? null : currentYear - birthYear;

/// The birth years that may be chosen in [currentYear], newest first.
List<int> birthYearChoices(int currentYear) => [
  for (
    var year = currentYear - Profile.minAge;
    year >= currentYear - Profile.maxAge;
    year--
  )
    year,
];

/// Whether [year] is a birth year the profile accepts in [currentYear].
bool isAcceptedBirthYear(int year, {required int currentYear}) {
  final age = currentYear - year;
  return age >= Profile.minAge && age <= Profile.maxAge;
}

/// Whether to offer the contraception mode. docs/cycle-logic.md §10.
///
/// Only for a hormonal method while in the natural-cycle mode: in any other
/// mode she has already chosen something that fits better than a guess from
/// here would, and a non-hormonal method leaves the cycle natural.
bool offersContraceptionMode(Profile profile, CycleSettings settings) =>
    (profile.contraception?.hormonal ?? false) &&
    settings.mode == CycleMode.natural;
