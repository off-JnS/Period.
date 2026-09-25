import 'package:period/domain/logic/cycle_report.dart';
import 'package:period/domain/logic/period_length.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/dates.dart';
import '../support/models.dart';

void main() {
  final today = aDate(2024, 12, 20);
  final starts = regularPeriodStarts(
    from: aDate(2024, 6, 1),
    length: 28,
    count: 7,
  );

  List<DayEntry> flowDays(CycleDate start, int days) => [
    for (var i = 0; i < days; i++)
      aDayEntry(date: start.addDays(i), flow: FlowIntensity.medium),
  ];

  CycleReport report({
    List<CycleDate>? periodStarts,
    List<DayEntry> entries = const [],
    CycleSettings settings = const CycleSettings(),
  }) => buildCycleReport(
    periodStarts: periodStarts ?? starts,
    entries: entries,
    settings: settings,
    today: today,
  );

  test('covers the year up to today', () {
    final r = report();
    expect(r.to, today);
    expect(r.from, today.subtractDays(reportDays));
  });

  test(
    'lists every cycle in range, newest first, in-progress without length',
    () {
      final r = report();
      expect(r.cycles.map((c) => c.start), starts.reversed);
      expect(r.cycles.first.cycleLength, isNull);
      expect(r.cycles.skip(1).map((c) => c.cycleLength), everyElement(28));
    },
  );

  test('leaves out cycles that started before the range', () {
    final old = aDate(2023, 6, 1);
    final r = report(periodStarts: [old, ...starts]);
    expect(r.cycles.map((c) => c.start), isNot(contains(old)));
  });

  test('states usual cycle length and range from completed cycles', () {
    final r = report();
    expect(r.usualCycleLength, 28);
    expect((r.shortestCycle, r.longestCycle), (28, 28));
  });

  test('hides cycle figures in pregnancy, but keeps the table (§6)', () {
    final r = report(settings: const CycleSettings(mode: CycleMode.pregnancy));
    expect(r.usualCycleLength, isNull);
    expect(r.shortestCycle, isNull);
    expect(r.longestCycle, isNull);
    expect(r.cycles, isNotEmpty);
    expect(r.mode, CycleMode.pregnancy);
  });

  test('gives each cycle its period length from the logged flow', () {
    final r = report(
      entries: [...flowDays(starts[0], 5), ...flowDays(starts[1], 4)],
    );
    final byStart = {for (final c in r.cycles) c.start: c.period};
    expect(byStart[starts[0]], const KnownPeriodLength(5));
    expect(byStart[starts[1]], const KnownPeriodLength(4));
    expect(byStart[starts[2]], const UnknownPeriodLength());
    expect(r.usualPeriodLength, 5); // median of 4 and 5, rounded
  });

  test('counts symptoms and moods by days, most often first', () {
    final r = report(
      entries: [
        aDayEntry(
          date: aDate(2024, 11, 1),
          symptoms: {
            aSymptom(key: 'cramps'),
            aSymptom(key: 'mood.sad'),
          },
        ),
        aDayEntry(
          date: aDate(2024, 11, 2),
          symptoms: {
            aSymptom(key: 'cramps'),
            aSymptom(key: 'headache'),
          },
        ),
      ],
    );
    expect(r.symptoms.map((c) => (c.key, c.days)), [
      ('cramps', 2),
      ('headache', 1),
    ]);
    expect(r.moods.map((c) => (c.key, c.days)), [('mood.sad', 1)]);
  });

  test('breaks ties in the order the app offers them', () {
    final r = report(
      entries: [
        aDayEntry(
          date: aDate(2024, 11, 1),
          symptoms: {
            aSymptom(key: 'nausea'),
            aSymptom(key: 'cramps'),
          },
        ),
      ],
    );
    expect(r.symptoms.map((c) => c.key), ['cramps', 'nausea']);
  });

  test('never includes notes, sex, discharge or the pill', () {
    final r = report(
      entries: [
        aDayEntry(
          date: aDate(2024, 11, 1),
          note: 'private',
          symptoms: {
            aSymptom(key: 'sex.unprotected'),
            aSymptom(key: 'discharge.creamy'),
            aSymptom(key: 'pill.taken'),
          },
        ),
      ],
    );
    final keys = [...r.symptoms, ...r.moods].map((c) => c.key);
    expect(keys, isEmpty);
  });

  test('ignores entries outside the range', () {
    final r = report(
      entries: [
        aDayEntry(
          date: aDate(2023, 1, 1),
          symptoms: {aSymptom(key: 'acne')},
        ),
      ],
    );
    expect(r.symptoms, isEmpty);
  });

  test('an empty history makes an empty, valid report', () {
    final r = report(periodStarts: []);
    expect(r.cycles, isEmpty);
    expect(r.usualCycleLength, isNull);
    expect(r.usualPeriodLength, isNull);
  });
}
