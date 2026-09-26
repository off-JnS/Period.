import 'package:period/domain/models/symptom.dart';
import 'package:test/test.dart';

/// The logged-key catalogues are stored by string forever (CLAUDE.md §5), so
/// their shape is pinned here: a key that changes or collides would silently
/// reinterpret what she logged.
void main() {
  final all = [
    ...offeredSymptomKeys,
    ...offeredMoodKeys,
    ...offeredDischargeKeys,
    ...offeredSexKeys,
    ...offeredOvulationTestKeys,
    ...offeredPregnancyTestKeys,
    pillTakenKey,
  ];

  test('no key appears twice across the catalogues', () {
    expect(all.toSet(), hasLength(all.length));
  });

  test('symptoms keep their original unprefixed keys', () {
    // Rows logged before moods existed must keep their meaning.
    expect(offeredSymptomKeys.where((key) => key.contains('.')), isEmpty);
  });

  test('every newer kind lives in its own namespace', () {
    expect(offeredMoodKeys, everyElement(startsWith('mood.')));
    expect(offeredDischargeKeys, everyElement(startsWith('discharge.')));
    expect(offeredSexKeys, everyElement(startsWith('sex.')));
    expect(pillTakenKey, startsWith('pill.'));
  });

  test('discharge and sex are single-choice, moods are not', () {
    expect(singleChoiceGroups, contains(offeredDischargeKeys));
    expect(singleChoiceGroups, contains(offeredSexKeys));
    expect(singleChoiceGroups, isNot(contains(offeredMoodKeys)));
  });

  test('keys are stable identifiers, not display text', () {
    expect(
      all,
      everyElement(matches(RegExp(r'^[a-z][a-zA-Z]*(\.[a-z][a-zA-Z]*)?$'))),
    );
  });
}
