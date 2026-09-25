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
    final days = 4 + index % 3;
    for (var day = 0; day < days; day++) {
      final flow = switch (day) {
        0 || 1 => FlowIntensity.heavy,
        2 => FlowIntensity.medium,
        _ => FlowIntensity.light,
      };
      await log.saveEntry(
        DayEntry(
          date: start.addDays(day),
          flow: flow,
          symptoms: {
            if (day == 0) const Symptom(key: 'cramps'),
            if (day == 0 && index.isEven) const Symptom(key: 'backache'),
            if (day == 1) const Symptom(key: 'fatigue'),
            if (day == 1) const Symptom(key: 'mood.sensitive'),
            if (day == 2 && index.isOdd) const Symptom(key: 'headache'),
            if (day == 3) const Symptom(key: 'mood.calm'),
          },
          note: day == 0 && index == 1 ? 'Heat pad helped a lot' : null,
        ),
      );
    }

    // A few days mid-cycle, for the other kinds of entry.
    if (index == 0) continue; // the current cycle is only 12 days old
    await log.saveEntry(
      DayEntry(
        date: start.addDays(9),
        symptoms: {
          const Symptom(key: 'discharge.creamy'),
          const Symptom(key: 'mood.energetic'),
          const Symptom(key: 'mood.happy'),
        },
      ),
    );
    await log.saveEntry(
      DayEntry(
        date: start.addDays(13),
        symptoms: {
          const Symptom(key: 'discharge.eggWhite'),
          Symptom(key: index.isEven ? 'sex.protected' : 'sex.none'),
        },
      ),
    );
    await log.saveEntry(
      DayEntry(
        date: start.addDays(23),
        symptoms: {
          const Symptom(key: 'bloating'),
          const Symptom(key: 'tenderBreasts'),
          const Symptom(key: 'mood.irritable'),
          if (index == 2) const Symptom(key: 'acne'),
        },
        note: index == 3 ? 'Slept badly all week' : null,
      ),
    );
  }

  // Today, so the "logged today" card has something in every line.
  await log.saveEntry(
    DayEntry(
      date: today,
      note: 'Long walk after work',
      symptoms: {
        const Symptom(key: 'mood.calm'),
        const Symptom(key: 'mood.energetic'),
        const Symptom(key: 'discharge.sticky'),
        const Symptom(key: 'sex.protected'),
        const Symptom(key: 'troubleSleeping'),
      },
    ),
  );

  // The fertile window is opt-in; on here so the preview shows it.
  await database.settingsDao.saveCycleSettings(
    const CycleSettings(fertileWindowOptedIn: true),
  );
}
