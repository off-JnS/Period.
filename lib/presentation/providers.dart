import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_lock.dart';
import '../data/backup/backup_service.dart';
import '../data/backup/backup_transfer.dart';
import '../data/database/daos/settings_dao.dart';
import '../data/database/database.dart';
import '../data/system_clock.dart';
import '../domain/logic/cycle_analysis.dart';
import '../domain/logic/fertile_window.dart';
import '../domain/logic/irregularity.dart';
import '../domain/logic/period_prediction.dart';
import '../domain/models/clock.dart';
import '../domain/models/cycle.dart';
import '../domain/models/cycle_date.dart';
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

/// Asks the device to confirm it is her, for section 9's optional lock.
///
/// Behind a seam like the backup transfer, so the gate's behaviour is testable
/// without a device -- including the case that matters most, where the device
/// cannot authenticate at all.
final appLockProvider = Provider<AppLock>((ref) => DeviceAppLock());

/// Whether this device can authenticate at all.
///
/// Read once and shown in settings, so the switch can explain itself rather
/// than sitting there refusing to move.
final lockAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockProvider).isAvailable(),
);

/// How a backup file leaves the app and comes back.
///
/// The only part of the backup that touches a platform plugin, so it is behind
/// a seam that tests override -- the export and import flows are checked
/// end to end without a share sheet or a file picker.
final backupTransferProvider = Provider<BackupTransfer>(
  (ref) => const SystemBackupTransfer(),
);

/// Makes and restores backups.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

/// The user's preferences, read from the database.
///
/// One provider for all of them rather than one each: they are one row set, one
/// read and one invalidation, and a screen that showed the mode from a fresh
/// read beside an opt-in from a stale one would be showing two different
/// moments at once.
///
/// A fresh install has no rows and gets the defaults -- a natural cycle with
/// predictions on. A stored value this build cannot read throws rather than
/// guessing; see [SettingsDao].
final settingsProvider = FutureProvider<StoredSettings>(
  (ref) => ref.watch(databaseProvider).settingsDao.readSettings(),
);

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
  final settings = ref.watch(settingsProvider);
  final starts = ref.watch(periodStartsProvider);

  // Both reads have to land before anything is computed. Showing a prediction
  // against default settings while the real ones are still loading would flash
  // an estimate at a user who has predictions turned off, which is the one
  // thing section 10 is there to prevent.
  return switch ((settings, starts)) {
    (AsyncError(:final error, :final stackTrace), _) ||
    (
      _,
      AsyncError(:final error, :final stackTrace),
    ) => AsyncError(error, stackTrace),
    (AsyncValue(:final value?), AsyncValue(value: final recorded?)) =>
      AsyncData(_todayFrom(today, recorded, value)),
    _ => const AsyncLoading(),
  };
});

TodayViewData _todayFrom(
  CycleDate today,
  List<CycleDate> starts,
  StoredSettings settings,
) {
  final prediction = predictNextPeriod(
    periodStarts: starts,
    settings: settings.cycle,
  );
  final eligible = eligibleForStatistics(cyclesFrom(starts));

  return TodayViewData(
    cycleDay: cycleDayOn(today, starts),
    typicalCycleLength: _typicalLength(eligible),
    prediction: prediction,
    fertileWindow: estimateFertileWindow(
      prediction: prediction,
      optedIn: settings.fertileWindowOptedIn,
    ),
    showDoctorHint: shouldSuggestSeeingADoctor(eligible),
  );
}

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
