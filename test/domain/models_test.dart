import 'package:period/domain/models/cycle.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/dates.dart';
import '../support/models.dart';

void main() {
  group('Symptom', () {
    test('is identified by its key', () {
      expect(aSymptom(key: 'cramps'), aSymptom(key: 'cramps'));
      expect(aSymptom(key: 'cramps'), isNot(aSymptom(key: 'headache')));
    });

    test('deduplicates in a Set, so logging one twice logs it once', () {
      final logged = {aSymptom(key: 'cramps'), aSymptom(key: 'cramps')};
      expect(logged, hasLength(1));
    });

    test('keys are opaque, so a new one needs no schema change', () {
      // Section 5: symptoms are keyed by string precisely so that adding one
      // never requires a migration. Any string is a valid key.
      const invented = 'a-symptom-nobody-thought-of-yet';
      expect(aSymptom(key: invented).key, invented);
    });
  });

  group('DayEntry', () {
    test('needs only a date', () {
      final entry = aDayEntry(date: aDate(2024, 5, 17));
      expect(entry.date, aDate(2024, 5, 17));
      expect(entry.flow, isNull);
      expect(entry.note, isNull);
      expect(entry.symptoms, isEmpty);
    });

    test('distinguishes "not recorded" from "recorded as none"', () {
      // This distinction is the reason section 5 makes every field but the date
      // nullable. A null flow means the user did not say; FlowIntensity.none
      // means she said there was no bleeding. Collapsing them would invent data.
      expect(aDayEntry().flow, isNull);
      expect(aDayEntry(flow: FlowIntensity.none).flow, FlowIntensity.none);
      expect(aDayEntry(), isNot(aDayEntry(flow: FlowIntensity.none)));
    });

    test('copyWith can set a nullable field back to null', () {
      // The subtle one. Hand-written copyWith usually cannot tell "omitted"
      // from "explicitly null", so clearing a note silently does nothing. This
      // asserts the generated implementation gets it right, because a user who
      // deletes a note expects it gone.
      final withNote = aDayEntry(note: 'sore');
      expect(withNote.copyWith(note: null).note, isNull);
    });

    test('copyWith leaves untouched fields alone', () {
      final entry = aDayEntry(
        date: aDate(2024, 5, 17),
        flow: FlowIntensity.medium,
        note: 'sore',
        symptoms: {aSymptom(key: 'cramps')},
      );
      final moved = entry.copyWith(date: aDate(2024, 5, 18));

      expect(moved.date, aDate(2024, 5, 18));
      expect(moved.flow, FlowIntensity.medium);
      expect(moved.note, 'sore');
      expect(moved.symptoms, entry.symptoms);
    });

    test('is compared by value, not identity', () {
      expect(
        aDayEntry(date: aDate(2024, 5, 17), note: 'sore'),
        aDayEntry(date: aDate(2024, 5, 17), note: 'sore'),
      );
      expect(
        aDayEntry(date: aDate(2024, 5, 17)),
        isNot(aDayEntry(date: aDate(2024, 5, 18))),
      );
    });

    test('carries several symptoms at once', () {
      final entry = aDayEntry(
        symptoms: {
          aSymptom(key: 'cramps'),
          aSymptom(key: 'headache'),
        },
      );
      expect(entry.symptoms, hasLength(2));
      expect(entry.symptoms, contains(aSymptom(key: 'cramps')));
    });

    test('every flow value survives a round trip through the model', () {
      for (final flow in FlowIntensity.values) {
        expect(aDayEntry(flow: flow).flow, flow);
      }
    });
  });

  group('Cycle', () {
    test('knows it is in progress when no later start exists', () {
      expect(aCycle(inProgress: true).isInProgress, isTrue);
      expect(aCycle().isInProgress, isFalse);
    });

    test('holds only what the data says, not what it implies', () {
      // Length, phase and fertile window are section 11's medical logic and are
      // deliberately absent until that specification exists. If this test starts
      // failing because someone added a computed field, the question is whether
      // the specification arrived first.
      final cycle = aCycle(start: aDate(2024, 1, 1), end: aDate(2024, 1, 28));
      expect(cycle.start, aDate(2024, 1, 1));
      expect(cycle.end, aDate(2024, 1, 28));
    });

    test('is compared by value', () {
      expect(
        aCycle(start: aDate(2024, 1, 1), end: aDate(2024, 1, 28)),
        aCycle(start: aDate(2024, 1, 1), end: aDate(2024, 1, 28)),
      );
      expect(
        aCycle(start: aDate(2024, 1, 1), end: aDate(2024, 1, 28)),
        isNot(aCycle(start: aDate(2024, 1, 1), inProgress: true)),
      );
    });

    test('a one-day cycle is representable', () {
      // Not medically meaningful, but the model must not refuse data the user
      // actually entered -- section 7's awkward cases start here.
      final sameDay = Cycle(start: aDate(2024, 1, 1), end: aDate(2024, 1, 1));
      expect(sameDay.start, sameDay.end);
      expect(sameDay.isInProgress, isFalse);
    });
  });
}
