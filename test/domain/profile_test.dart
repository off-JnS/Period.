import 'package:period/domain/logic/profile.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:test/test.dart';

void main() {
  group('ageThisYear', () {
    test('is the age she turns this calendar year', () {
      expect(ageThisYear(birthYear: 1998, currentYear: 2026), 28);
    });

    test('is null without a birth year', () {
      expect(ageThisYear(birthYear: null, currentYear: 2026), isNull);
    });
  });

  group('birth years', () {
    test('run newest first from the youngest to the oldest accepted age', () {
      final years = birthYearChoices(2026);
      expect(years.first, 2026 - Profile.minAge);
      expect(years.last, 2026 - Profile.maxAge);
      expect(years, orderedEquals([...years]..sort((a, b) => b - a)));
      expect(years.length, Profile.maxAge - Profile.minAge + 1);
    });

    test('are accepted at both ends of the range and refused outside it', () {
      expect(isAcceptedBirthYear(2018, currentYear: 2026), isTrue);
      expect(isAcceptedBirthYear(1956, currentYear: 2026), isTrue);
      expect(isAcceptedBirthYear(2019, currentYear: 2026), isFalse);
      expect(isAcceptedBirthYear(1955, currentYear: 2026), isFalse);
      expect(isAcceptedBirthYear(2030, currentYear: 2026), isFalse);
    });

    test('every offered year is accepted', () {
      for (final year in birthYearChoices(2026)) {
        expect(isAcceptedBirthYear(year, currentYear: 2026), isTrue);
      }
    });
  });

  group('offersContraceptionMode', () {
    const natural = CycleSettings();

    test('offers for every hormonal method in the natural mode', () {
      for (final method in ContraceptionMethod.values.where(
        (m) => m.hormonal,
      )) {
        expect(
          offersContraceptionMode(Profile(contraception: method), natural),
          isTrue,
          reason: method.name,
        );
      }
    });

    test('never offers for a method that leaves the cycle natural', () {
      for (final method in [
        ContraceptionMethod.none,
        ContraceptionMethod.condom,
        ContraceptionMethod.copperIud,
        ContraceptionMethod.other,
      ]) {
        expect(
          offersContraceptionMode(Profile(contraception: method), natural),
          isFalse,
          reason: method.name,
        );
      }
    });

    test('never offers without a method', () {
      expect(offersContraceptionMode(const Profile(), natural), isFalse);
    });

    test('never offers outside the natural mode', () {
      const pill = Profile(contraception: ContraceptionMethod.combinedPill);
      for (final mode in CycleMode.values.where(
        (m) => m != CycleMode.natural,
      )) {
        expect(
          offersContraceptionMode(pill, CycleSettings(mode: mode)),
          isFalse,
          reason: mode.name,
        );
      }
    });
  });

  group('Profile', () {
    test('is empty until something is said', () {
      expect(const Profile().isEmpty, isTrue);
      expect(const Profile(birthYear: 1990).isEmpty, isFalse);
      expect(
        const Profile(conditions: {KnownCondition.pcos}).isEmpty,
        isFalse,
      );
      expect(
        const Profile(contraception: ContraceptionMethod.none).isEmpty,
        isFalse,
      );
    });

    test('accepts the documented ranges', () {
      expect(Profile.minCycleLength, 15);
      expect(Profile.maxCycleLength, 90);
      expect(Profile.minPeriodLength, 1);
      expect(Profile.maxPeriodLength, 14);
    });
  });
}
