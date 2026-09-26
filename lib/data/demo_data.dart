import 'package:flutter/foundation.dart';

import '../domain/models/cycle_date.dart';
import '../domain/models/cycle_mode.dart';
import '../domain/models/day_entry.dart';
import '../domain/models/symptom.dart';
import 'database/database.dart';

/// Whether this build was asked to fill an empty database with made-up data,
/// so every screen can be previewed:
///
///     flutter run --dart-define=PERIOD_DEMO_DATA=true
///
/// Never in a release build, whatever the flag says: a user must never find
/// a stranger's cycle in her app.
const demoDataRequested =
    bool.fromEnvironment('PERIOD_DEMO_DATA') && !kReleaseMode;

/// Cycle lengths, newest completed cycle first.
///
/// Chosen to light up every feature at once: regular enough for an estimate
/// window (the interquartile spread stays small), yet with one 38-day cycle so
/// the range passes nine days and the "worth mentioning to a doctor" hint shows.
const _cycleLengths = [28, 30, 26, 38, 29, 27, 28];

/// Today's day in the current cycle: late enough that the estimate and the
/// fertile window are both still ahead.
const _currentCycleDay = 12;

/// Fills [database] with eight months of made-up history ending on [today].
///
/// Only for previewing; see [demoDataRequested]. Everything is placed relative
/// to [today] so the preview always looks current.
Future<void> seedDemoData(AppDatabase database, CycleDate today) async {
  final log = database.logDao;
  final days = <CycleDate, DayEntry>{};

  /// Merges into whatever that day already has, so kinds of entry placed by
  /// different rules below never overwrite each other.
  void add(
    CycleDate date, {
    FlowIntensity? flow,
    String? note,
    int? temperature,
    Set<String> keys = const {},
  }) {
    final existing = days[date] ?? DayEntry(date: date, symptoms: const {});
    days[date] = existing.copyWith(
      flow: flow ?? existing.flow,
      note: note ?? existing.note,
      temperatureCentiCelsius: temperature ?? existing.temperatureCentiCelsius,
      symptoms: {
        ...existing.symptoms,
        for (final key in keys) Symptom(key: key),
      },
    );
  }

  // Period starts, walking back from the current cycle.
  var start = today.subtractDays(_currentCycleDay - 1);
  final starts = <CycleDate>[start];
  for (final length in _cycleLengths) {
    start = start.subtractDays(length);
    starts.add(start);
  }

  for (final (index, start) in starts.indexed) {
    await log.addPeriodStart(start);

    // Period days: heavier first, tapering; four to six days long.
    final periodDays = 4 + index % 3;
    for (var day = 0; day < periodDays; day++) {
      add(
        start.addDays(day),
        flow: switch (day) {
          0 || 1 => FlowIntensity.heavy,
          2 => FlowIntensity.medium,
          _ => FlowIntensity.light,
        },
        note: day == 0 && index == 1 ? 'Heat pad helped a lot' : null,
        keys: {
          if (day == 0) 'cramps',
          if (day == 0 && index.isEven) 'backache',
          if (day == 1) 'fatigue',
          if (day == 1) 'mood.sensitive',
          if (day == 2 && index.isOdd) 'headache',
          if (day == 3) 'mood.calm',
        },
      );
    }

    // A few days mid-cycle, for the other kinds of entry.
    if (index == 0) continue; // the current cycle is only 12 days old
    add(
      start.addDays(9),
      keys: {'discharge.creamy', 'mood.energetic', 'mood.happy'},
    );
    add(
      start.addDays(13),
      keys: {'discharge.eggWhite', index.isEven ? 'sex.protected' : 'sex.none'},
    );
    add(
      start.addDays(23),
      note: index == 3 ? 'Slept badly all week' : null,
      keys: {
        'bloating',
        'tenderBreasts',
        'mood.irritable',
        if (index == 2) 'acne',
      },
    );
  }

  // Temperatures for the current cycle so far, so the chart has a curve:
  // a lower phase with the small day-to-day wobble real readings have.
  const wobble = [0, 5, -3, 8, 2, -6, 4, 7, -2, 3, 6, 1];
  for (var day = 0; day < _currentCycleDay; day++) {
    add(
      starts[0].addDays(day),
      temperature: 3635 + wobble[day % wobble.length],
    );
  }
  // Ovulation tests in the previous cycle: negative, then positive.
  for (final (day, result) in [
    (10, 'negative'),
    (11, 'negative'),
    (12, 'positive'),
  ]) {
    add(starts[1].addDays(day), keys: {'ovulationTest.$result'});
  }

  // Pregnancy tests: one on a day with sex, so the calendar shows the heart
  // and the ± side by side, and one late in the last cycle. Both negative:
  // the demo shows the mark, not a story.
  add(starts[2].addDays(13), keys: {'pregnancyTest.negative'});
  add(starts[1].addDays(24), keys: {'pregnancyTest.negative'});

  // Today, so the "logged today" card has something in every line.
  add(
    today,
    note: 'Long walk after work',
    keys: {
      'mood.calm',
      'mood.energetic',
      'discharge.sticky',
      'sex.protected',
      'troubleSleeping',
      'ovulationTest.negative',
    },
  );

  for (final entry in days.values) {
    await log.saveEntry(entry);
  }

  // The fertile window is opt-in; on here so the preview shows it.
  await database.settingsDao.saveCycleSettings(
    const CycleSettings(fertileWindowOptedIn: true),
  );
}
