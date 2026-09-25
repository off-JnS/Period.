import 'package:period/data/database/database.dart';
import 'package:period/data/demo_data.dart';
import 'package:period/domain/logic/cycle_analysis.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/irregularity.dart';
import 'package:period/domain/logic/period_length.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:test/test.dart';

import '../support/database.dart';
import '../support/dates.dart';

/// The demo data exists to show every feature at once. If a change to the
/// estimate rules quietly stopped it doing so, the preview would mislead
/// whoever is reviewing; these pin it.
void main() {
  late AppDatabase database;
  final today = aDate(2024, 5, 17);

  setUp(() async {
    database = aDatabase();
    await seedDemoData(database, today);
  });
  tearDown(() => database.close());

  test('is never on unless asked for', () {
    // The test runner passes no --dart-define, like any normal build.
    expect(demoDataRequested, isFalse);
  });

  test('today is day 12 of a cycle', () async {
    final starts = await database.logDao.allPeriodStarts();
    expect(cycleDayOn(today, starts), 12);
  });

  test('there is a period estimate and a fertile window', () async {
    final starts = await database.logDao.allPeriodStarts();
    final settings = await database.settingsDao.cycleSettings();
    final prediction = predictNextPeriod(
      periodStarts: starts,
      settings: settings,
    );
    expect(prediction, isA<PredictedPeriod>());
    expect(
      estimateFertileWindow(
        prediction: prediction,
        optedIn: settings.fertileWindowOptedIn,
      ),
      isNotNull,
    );
  });

  test('the doctor hint shows', () async {
    final starts = await database.logDao.allPeriodStarts();
    final eligible = eligibleForStatistics(cyclesFrom(starts));
    expect(shouldSuggestSeeingADoctor(eligible), isTrue);
  });

  test('period lengths are known, so "usually" appears', () async {
    final starts = await database.logDao.allPeriodStarts();
    final entries = await database.logDao.entriesBetween(starts.first, today);
    final lengths = periodLengths(
      starts: starts,
      flowByDay: {for (final e in entries) e.date: ?e.flow},
      today: today,
    );
    expect(usualPeriodLength(lengths), isNotNull);
  });

  test("today's entry has every kind of thing to log", () async {
    final entry = await database.logDao.entryOn(today);
    final keys = entry!.symptoms.map((symptom) => symptom.key);
    expect(
      keys,
      containsAll(['mood.calm', 'discharge.sticky', 'sex.protected']),
    );
    expect(entry.note, isNotEmpty);
  });

  test('every date is on or before today', () async {
    final starts = await database.logDao.allPeriodStarts();
    expect(starts.every((start) => !start.isAfter(today)), isTrue);
    final entries = await database.logDao.entriesBetween(
      starts.first,
      today.addDays(400),
    );
    expect(entries.every((entry) => !entry.date.isAfter(today)), isTrue);
  });

  test('the current cycle has temperatures for the chart', () async {
    final starts = await database.logDao.allPeriodStarts();
    final entries = await database.logDao.entriesBetween(starts.last, today);
    final readings = entries.where((e) => e.temperatureCentiCelsius != null);
    expect(readings.length, greaterThanOrEqualTo(2));
    expect(
      readings.every(
        (e) =>
            e.temperatureCentiCelsius! >= 3400 &&
            e.temperatureCentiCelsius! <= 4300,
      ),
      isTrue,
    );
  });

  test('flow and temperature on the same day both survive', () async {
    final starts = await database.logDao.allPeriodStarts();
    final first = await database.logDao.entryOn(starts.last);
    expect(first!.flow, isNotNull);
    expect(first.temperatureCentiCelsius, isNotNull);
  });
}
