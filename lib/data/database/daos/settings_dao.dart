import 'package:drift/drift.dart';

import '../../../domain/models/cycle_mode.dart';
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
