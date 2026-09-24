import 'package:drift/drift.dart';

import '../../../domain/models/app_preferences.dart';
import '../../../domain/models/cycle_mode.dart';
import '../database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

/// The keys settings are stored under. Stable: renaming one orphans the value
/// already on users' devices.
abstract final class SettingKeys {
  /// Which [CycleMode] the user is in, by enum name.
  static const cycleMode = 'cycle_mode';

  /// `true` when a perimenopause user asked for predictions anyway.
  static const predictionsOptedIn = 'predictions_opted_in';

  /// `true` when the user asked to see the estimated fertile window.
  static const fertileWindowOptedIn = 'fertile_window_opted_in';

  /// Which [AppearanceChoice], by enum name.
  static const appearance = 'appearance';

  /// Which [LanguageChoice], by enum name.
  static const language = 'language';
}

/// Reads and writes the user's settings.
@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  /// Creates the accessor.
  SettingsDao(super.attachedDatabase);

  /// The stored cycle settings, with the defaults for anything not stored.
  ///
  /// A value this build does not recognise -- written by a newer version, say,
  /// then downgraded -- reads as the default rather than throwing. Failing to
  /// start over a setting would lock her out of her own data.
  Future<CycleSettings> cycleSettings() async {
    final values = await _values();

    return CycleSettings(
      mode:
          CycleMode.values.asNameMap()[values[SettingKeys.cycleMode]] ??
          CycleMode.natural,
      predictionsOptedIn: values[SettingKeys.predictionsOptedIn] == 'true',
      fertileWindowOptedIn: values[SettingKeys.fertileWindowOptedIn] == 'true',
    );
  }

  /// Stores [settings], replacing whatever was there.
  ///
  /// One transaction, so the settings can never be half-written: a mode from
  /// one save paired with an opt-in from another is a state she never chose.
  Future<void> saveCycleSettings(CycleSettings settings) async {
    await transaction(() async {
      await _put(SettingKeys.cycleMode, settings.mode.name);
      await _put(
        SettingKeys.predictionsOptedIn,
        '${settings.predictionsOptedIn}',
      );
      await _put(
        SettingKeys.fertileWindowOptedIn,
        '${settings.fertileWindowOptedIn}',
      );
    });
  }

  /// The stored appearance and language, with the defaults for anything not
  /// stored or not understood.
  Future<AppPreferences> appPreferences() async {
    final values = await _values();
    return AppPreferences(
      appearance:
          AppearanceChoice.values.asNameMap()[values[SettingKeys.appearance]] ??
          AppearanceChoice.system,
      language:
          LanguageChoice.values.asNameMap()[values[SettingKeys.language]] ??
          LanguageChoice.system,
    );
  }

  /// Stores [preferences], replacing whatever was there.
  Future<void> saveAppPreferences(AppPreferences preferences) async {
    await transaction(() async {
      await _put(SettingKeys.appearance, preferences.appearance.name);
      await _put(SettingKeys.language, preferences.language.name);
    });
  }

  Future<Map<String, String>> _values() async {
    final rows = await select(appSettings).get();
    return {for (final row in rows) row.settingKey: row.settingValue};
  }

  Future<void> _put(String key, String value) => into(appSettings).insert(
    AppSettingsCompanion.insert(settingKey: key, settingValue: value),
    mode: InsertMode.replace,
  );
}
