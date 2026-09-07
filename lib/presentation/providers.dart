import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/system_clock.dart';
import '../domain/logic/cycle_analysis.dart';
import '../domain/logic/fertile_window.dart';
import '../domain/logic/irregularity.dart';
import '../domain/logic/period_prediction.dart';
import '../domain/models/clock.dart';
import '../domain/models/cycle.dart';
import '../domain/models/cycle_date.dart';
import '../domain/models/cycle_mode.dart';
import '../domain/models/day_entry.dart';
import 'today/today_screen.dart';

/// The open database.
///
/// Deliberately has no default. Opening the real one is asynchronous and
/// platform-bound, so `main` overrides this once at startup and every test
/// overrides it with an in-memory database. A provider that quietly created a
/// real database on first read would put a file on disk during tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'Override databaseProvider with an opened AppDatabase.',
  ),
);

/// Today's date. The single place the app asks what day it is.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// The user's cycle mode.
///
/// Not persisted yet: choosing a mode needs a settings screen, and storing it
/// needs a schema migration, which section 5 says not to write casually. The
/// default is a natural cycle with predictions on, so the logic path exercised
/// here is the one most users see.
final cycleSettingsProvider = Provider<CycleSettings>(
  (ref) => const CycleSettings(),
);

/// Whether the user has opted into the fertile window estimate.
///
/// Off by default, per docs/cycle-logic.md. Persisting the choice waits on the
/// same settings screen.
final fertileWindowOptedInProvider = Provider<bool>((ref) => false);

/// Every period start the user has recorded, oldest first.
///
/// A one-shot read that callers invalidate after writing, rather than a live
/// stream. There is exactly one writer -- this app, on this device -- so
/// nothing can change the data behind the UI's back, and the simpler shape
/// avoids a long-lived subscription that outlives the widget that wanted it.
final periodStartsProvider = FutureProvider<List<CycleDate>>(
  (ref) => ref.watch(databaseProvider).logDao.allPeriodStarts(),
);

/// What the user logged on a given day.
final dayEntryProvider = FutureProvider.family<DayEntry?, CycleDate>(
  (ref, date) => ref.watch(databaseProvider).logDao.entryOn(date),
);

/// Every day with an entry between the two dates, inclusive.
///
/// A set rather than a list: the calendar asks "is this day logged?" once per
/// cell, forty-two times a month, and a linear scan per cell would be the only
/// slow thing on the screen.
///
/// Keyed by a record, so two screens showing the same range share one read and
/// a different range is a different entry. Records compare structurally and
/// [CycleDate] implements `==`, so this needs no key type of its own.
final loggedDaysProvider =
    FutureProvider.family<Set<CycleDate>, (CycleDate, CycleDate)>((
      ref,
      range,
    ) async {
      final entries = await ref
          .watch(databaseProvider)
          .logDao
          .entriesBetween(range.$1, range.$2);
      return {for (final entry in entries) entry.date};
    });

/// Everything the Today screen shows, derived from the stored period starts.
///
/// All of it computed on read, per section 4 — nothing here is stored, so a
/// retroactively corrected start date changes every number on the screen the
/// moment it is saved.
final todayViewDataProvider = Provider<AsyncValue<TodayViewData>>((ref) {
  final today = ref.watch(clockProvider).today();
  final settings = ref.watch(cycleSettingsProvider);

  return ref.watch(periodStartsProvider).whenData((starts) {
    final prediction = predictNextPeriod(
      periodStarts: starts,
      settings: settings,
    );
    final eligible = eligibleForStatistics(cyclesFrom(starts));

    return TodayViewData(
      cycleDay: cycleDayOn(today, starts),
      typicalCycleLength: _typicalLength(eligible),
      prediction: prediction,
      fertileWindow: estimateFertileWindow(
        prediction: prediction,
        optedIn: ref.watch(fertileWindowOptedInProvider),
      ),
      showDoctorHint: shouldSuggestSeeingADoctor(eligible),
    );
  });
});

/// The length the ring fills against, or null when there is not enough history.
///
/// Null rather than 28: only about 13% of cycles are 28 days, so a default
/// would draw a ring against a length that is probably not hers.
int? _typicalLength(List<Cycle> eligibleCycles) {
  if (eligibleCycles.isEmpty) return null;
  final lengths = [for (final cycle in eligibleCycles) ?cycle.lengthInDays]
    ..sort();
  if (lengths.isEmpty) return null;
  return lengths[lengths.length ~/ 2];
}
