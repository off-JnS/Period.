import 'package:period/domain/logic/logged_summary.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:test/test.dart';

import '../support/dates.dart';
import '../support/models.dart';

/// Descriptive statistics, per docs/cycle-logic.md section 1.
///
/// The definition being implemented, verbatim: "the run of consecutive days
/// from the period start with flow recorded as light, medium or heavy. A day
/// recorded as `none`, or a day with no flow recorded at all, ends the run."
void main() {
  DayEntry bleedingOn(int day, [FlowIntensity flow = FlowIntensity.medium]) =>
      aDayEntry(date: aDate(2024, 4, day), flow: flow);

  group('period duration', () {
    test('is zero when nothing was logged at all', () {
      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay([])), 0);
    });

    test('is zero when the start day itself has no flow recorded', () {
      // Not a missing value. She marked a start without logging flow, which is
      // common and not an error, and zero is the honest answer.
      final entries = [aDayEntry(date: aDate(2024, 4, 1), note: 'busy day')];

      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay(entries)), 0);
    });

    test('counts consecutive bleeding days', () {
      final entries = [bleedingOn(1), bleedingOn(2), bleedingOn(3)];

      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay(entries)), 3);
    });

    test('counts every intensity that is bleeding', () {
      final entries = [
        bleedingOn(1, FlowIntensity.heavy),
        bleedingOn(2, FlowIntensity.medium),
        bleedingOn(3, FlowIntensity.light),
      ];

      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay(entries)), 3);
    });

    test('a day recorded as none ends the run', () {
      // She logged something, and what she logged was the absence of flow.
      final entries = [
        bleedingOn(1),
        bleedingOn(2),
        bleedingOn(3, FlowIntensity.none),
        bleedingOn(4),
      ];

      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay(entries)), 2);
    });

    test('a day with nothing recorded ends the run', () {
      // Section 5 keeps "not recorded" meaningfully different from `none`, but
      // for a duration both end it: an unlogged day is not evidence of
      // bleeding.
      final entries = [bleedingOn(1), bleedingOn(2), bleedingOn(4)];

      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay(entries)), 2);
    });

    test('flow logged before the start does not count', () {
      final entries = [bleedingOn(1), bleedingOn(2), bleedingOn(3)];

      expect(periodDurationFrom(aDate(2024, 4, 2), flowByDay(entries)), 2);
    });

    test('a single day is a duration of one', () {
      expect(
        periodDurationFrom(aDate(2024, 4, 1), flowByDay([bleedingOn(1)])),
        1,
      );
    });

    test('a run longer than FIGO calls normal is reported, not clamped', () {
      // FIGO puts normal at 2 to 7 days. The document is explicit that the app
      // reports what was logged: a number outside that range is a fact about
      // her, not a mistake to correct.
      final entries = [for (var day = 1; day <= 11; day++) bleedingOn(day)];

      expect(periodDurationFrom(aDate(2024, 4, 1), flowByDay(entries)), 11);
    });

    test('runs across a month boundary', () {
      final entries = [
        aDayEntry(date: aDate(2024, 4, 29), flow: FlowIntensity.medium),
        aDayEntry(date: aDate(2024, 4, 30), flow: FlowIntensity.medium),
        aDayEntry(date: aDate(2024, 5, 1), flow: FlowIntensity.light),
      ];

      expect(periodDurationFrom(aDate(2024, 4, 29), flowByDay(entries)), 3);
    });

    test('runs across a leap day', () {
      final entries = [
        aDayEntry(date: aDate(2024, 2, 28), flow: FlowIntensity.medium),
        aDayEntry(date: aDate(2024, 2, 29), flow: FlowIntensity.medium),
        aDayEntry(date: aDate(2024, 3, 1), flow: FlowIntensity.light),
      ];

      expect(periodDurationFrom(aDate(2024, 2, 28), flowByDay(entries)), 3);
    });
  });

  group('symptom tallies', () {
    DayEntry withSymptoms(int day, List<String> keys) => aDayEntry(
      date: aDate(2024, 4, day),
      symptoms: {for (final key in keys) Symptom(key: key)},
    );

    test('nothing logged is an empty list, not a zero row', () {
      expect(symptomTallies([]), isEmpty);
    });

    test('counts the days each symptom appears on', () {
      final entries = [
        withSymptoms(1, ['cramps', 'headache']),
        withSymptoms(2, ['cramps']),
        withSymptoms(3, ['cramps', 'tiredness']),
      ];

      final tallies = symptomTallies(entries);
      expect(tallies.first.symptom.key, 'cramps');
      expect(tallies.first.days, 3);
    });

    test('most frequent first', () {
      final entries = [
        withSymptoms(1, ['headache']),
        withSymptoms(2, ['cramps']),
        withSymptoms(3, ['cramps']),
      ];

      expect(
        [for (final tally in symptomTallies(entries)) tally.symptom.key],
        ['cramps', 'headache'],
      );
    });

    test('ties break by key, so the order does not reshuffle', () {
      // A list that reordered between builds would look like the data changed
      // when it did not.
      final entries = [
        withSymptoms(1, ['tiredness', 'bloating', 'cramps']),
      ];

      expect(
        [for (final tally in symptomTallies(entries)) tally.symptom.key],
        ['bloating', 'cramps', 'tiredness'],
      );
    });

    test('a symptom on a day with nothing else still counts', () {
      // LogDao treats a day with symptoms and no entry row as a logged day, so
      // this must too -- it is the case the backup export nearly dropped.
      expect(
        symptomTallies([
          withSymptoms(1, ['tiredness']),
        ]).single.days,
        1,
      );
    });

    test('a key this build has never heard of is counted, not dropped', () {
      // Restored from a newer version. Showing it is better than losing it;
      // the presentation layer falls back to the raw key.
      final tallies = symptomTallies([
        withSymptoms(1, ['something_new']),
      ]);

      expect(tallies.single.symptom.key, 'something_new');
    });
  });

  group('median days', () {
    test('is null with nothing to average', () {
      expect(medianDays([]), isNull);
    });

    test('is the middle value of an odd count', () {
      expect(medianDays([3, 9, 5]), 5);
    });

    test('rounds up rather than truncating on an even count', () {
      // Days are whole things; half a day of bleeding is not a number she has
      // any use for, and truncating would report 4 for someone whose periods
      // run 4 and 5.
      expect(medianDays([4, 5]), 5);
    });

    test('one outlier does not drag it', () {
      // The reason docs/cycle-logic.md uses a median for cycle lengths: an
      // illness or a missed log must not move the number she reads as typical.
      expect(medianDays([28, 29, 30, 91]), 30);
    });

    test('does not reorder the caller list', () {
      final values = [9, 3, 5];
      medianDays(values);
      expect(values, [9, 3, 5]);
    });
  });

  test('days logged counts entries, not symptoms', () {
    final entries = [
      aDayEntry(date: aDate(2024, 4, 1), flow: FlowIntensity.heavy),
      aDayEntry(date: aDate(2024, 4, 2)),
    ];

    expect(daysLogged(entries), 2);
  });
}
