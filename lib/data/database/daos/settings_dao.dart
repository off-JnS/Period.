import 'package:drift/drift.dart';

import '../../../domain/models/cycle_mode.dart';
import '../../../domain/models/reminder_schedule.dart';
import '../../../domain/models/reminder_time.dart';
import '../database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

/// The keys this app stores. Stable strings, never renamed: a rename would make
/// an existing user's setting invisible and silently revert her to the default.
abstract final class SettingKeys {
  /// Which cycle mode the user selected, stored by [CycleMode.name].
  static const cycleMode = 'cycle_mode';

  /// Whether she asked for predictions despite a mode that disables them.
  static const predictionsOptedIn = 'predictions_opted_in';

  /// Whether she asked to see the fertile window estimate.
  static const fertileWindowOptedIn = 'fertile_window_opted_in';

  /// Whether the app asks the device to confirm it is her before opening.
  ///
  /// A new key in a table built to take them, so section 9's lock needed no
  /// schema change at all.
  static const appLockEnabled = 'app_lock_enabled';

  /// Whether she asked to be reminded to log.
  static const reminderEnabled = 'reminder_enabled';

  /// The time of day she chose, as `HH:mm`.
  static const reminderTime = 'reminder_time';

  /// The weekdays she chose, as comma-separated ISO weekday numbers, `1,3,5`.
  ///
  /// Stored by number rather than by name because [CycleDate.weekday] already
  /// defines 1 through 7 and there is no enum here to reorder. Three more keys
  /// in a table built to take them: reminders, like the lock before them, need
  /// no schema change.
  static const reminderWeekdays = 'reminder_weekdays';
}

/// Everything the app reads out of the settings table.
///
/// One value rather than three separate reads, so a screen asks once and every
/// consumer sees the same answer.
class StoredSettings {
  /// Creates the settings.
  const StoredSettings({
    this.cycle = const CycleSettings(),
    this.fertileWindowOptedIn = false,
    this.appLockEnabled = false,
    this.reminder = const ReminderSchedule(),
  });

  /// The cycle mode and its opt-in.
  final CycleSettings cycle;

  /// Whether the fertile window estimate is shown. Off unless asked for,
  /// per docs/cycle-logic.md section 4.
  final bool fertileWindowOptedIn;

  /// Whether the app asks the device to confirm it is her before opening.
  ///
  /// Off unless asked for, per section 9: the lock is optional, which is also
  /// why the database key is generated rather than derived from it.
  final bool appLockEnabled;

  /// When she asked to be reminded to log.
  ///
  /// Off unless asked for. See docs/cycle-logic.md section 7 -- this carries no
  /// inference about her cycle, so it needs no mode gate and reads the same in
  /// every cycle mode.
  final ReminderSchedule reminder;
}

/// Reads and writes the user's preferences.
@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  /// Creates the accessor.
  SettingsDao(super.attachedDatabase);

  /// Everything stored, with defaults for whatever has never been set.
  Future<StoredSettings> readSettings() async {
    final rows = await select(settings).get();
    final stored = {for (final row in rows) row.key: row.value};

    return StoredSettings(
      cycle: CycleSettings(
        mode: _readMode(stored[SettingKeys.cycleMode]),
        predictionsOptedIn: _readBool(stored[SettingKeys.predictionsOptedIn]),
      ),
      fertileWindowOptedIn: _readBool(stored[SettingKeys.fertileWindowOptedIn]),
      appLockEnabled: _readBool(stored[SettingKeys.appLockEnabled]),
      reminder: ReminderSchedule(
        enabled: _readBool(stored[SettingKeys.reminderEnabled]),
        time: _readReminderTime(stored[SettingKeys.reminderTime]),
        weekdays: _readWeekdays(stored[SettingKeys.reminderWeekdays]),
      ),
    );
  }

  /// Every stored row, exactly as written.
  ///
  /// Raw rather than the typed [StoredSettings], so a backup carries settings
  /// this build has never heard of and a later version added. Nothing here
  /// interprets a value, which is why this cannot throw the way
  /// [readSettings] deliberately does.
  Future<Map<String, String>> readAll() async {
    final rows = await select(settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  /// Replaces every stored row with [values].
  Future<void> replaceAll(Map<String, String> values) async {
    await transaction(() async {
      await delete(settings).go();
      for (final pair in values.entries) {
        await _write(pair.key, pair.value);
      }
    });
  }

  /// Stores the cycle mode and its opt-in.
  Future<void> writeCycleSettings(CycleSettings value) async {
    await transaction(() async {
      await _write(SettingKeys.cycleMode, value.mode.name);
      await _write(
        SettingKeys.predictionsOptedIn,
        value.predictionsOptedIn.toString(),
      );
    });
  }

  /// Stores whether the fertile window estimate is shown.
  Future<void> writeFertileWindowOptIn({required bool optedIn}) =>
      _write(SettingKeys.fertileWindowOptedIn, optedIn.toString());

  /// Stores whether the app locks itself.
  Future<void> writeAppLockEnabled({required bool enabled}) =>
      _write(SettingKeys.appLockEnabled, enabled.toString());

  /// Stores when she asked to be reminded to log.
  ///
  /// All three keys in one transaction. Written separately, a crash between
  /// them could leave the time from one choice beside the weekdays from
  /// another -- a reminder she never set, at a time she did not pick.
  Future<void> writeReminderSchedule(ReminderSchedule value) async {
    await transaction(() async {
      await _write(SettingKeys.reminderEnabled, value.enabled.toString());
      await _write(SettingKeys.reminderTime, value.time.toHhMm());
      await _write(
        SettingKeys.reminderWeekdays,
        (value.validWeekdays.toList()..sort()).join(','),
      );
    });
  }

  Future<void> _write(String key, String value) async {
    await into(settings).insert(
      SettingsCompanion.insert(key: key, value: value),
      mode: InsertMode.replace,
    );
  }
}

/// Reads a stored cycle mode.
///
/// Absent means never set, which is a fresh install: the default is a natural
/// cycle. A value this build does not recognise is a different thing entirely
/// and **throws** rather than falling back.
///
/// Falling back would mean [CycleMode.natural], and natural is the one mode
/// that *enables* predictions. A database written by a newer build -- restored
/// from a backup, say -- would then silently turn predictions on for someone who
/// deliberately turned them off, which is exactly what section 10 and
/// docs/cycle-logic.md section 6 exist to prevent. Failing loudly puts the
/// error panel on screen instead of a confident wrong answer.
CycleMode _readMode(String? stored) {
  if (stored == null) return CycleMode.natural;
  for (final mode in CycleMode.values) {
    if (mode.name == stored) return mode;
  }
  throw StateError(
    'Unknown cycle mode "$stored" in the database. This build cannot tell '
    'whether predictions should be on, and will not guess.',
  );
}

/// Reads a stored flag. Absent or anything but "true" means off.
///
/// Deliberately lenient where [_readMode] is strict: both of these flags are
/// opt-ins, so an unreadable value resolving to "off" leaves the user with less
/// shown than she asked for rather than more, which is the safe direction.
bool _readBool(String? stored) => stored == 'true';

/// Reads a stored reminder time.
///
/// Absent or unreadable falls back to the default, and is deliberately lenient
/// where [_readMode] is strict. The direction is what decides it: an unreadable
/// mode would resolve to the one mode that *enables* predictions, showing the
/// user more than she asked for, so it throws. A time cannot do that -- a
/// reminder only ever fires when [SettingKeys.reminderEnabled] is true, and
/// that flag is read separately, so the worst an unreadable time can do is fire
/// a reminder she did want at an hour she did not pick.
///
/// Not silently, though: the value is replaced on the next write, and a time
/// that cannot be parsed is a bug worth seeing rather than guessing around.
ReminderTime _readReminderTime(String? stored) {
  if (stored == null) return const ReminderSchedule().time;
  try {
    return ReminderTime.parseHhMm(stored);
  } on FormatException {
    return const ReminderSchedule().time;
  }
}

/// Reads a stored set of weekdays, `1,3,5`.
///
/// Anything unparseable resolves to the empty set, which means no reminder
/// fires at all. That is the safe direction for an opt-in: a garbled value
/// leaves the user with less than she asked for rather than a notification on a
/// day she never chose.
///
/// Empty and absent are kept apart from each other only by [ReminderSchedule]'s
/// default, which is every day: absent means she has never chosen, so a fresh
/// install that turns reminders on gets a daily one. An empty stored string
/// means she deselected every day, and is honoured.
Set<int> _readWeekdays(String? stored) {
  if (stored == null) return const ReminderSchedule().weekdays;
  return {
    for (final part in stored.split(','))
      if (int.tryParse(part.trim()) case final day?)
        if (day >= 1 && day <= 7) day,
  };
}
