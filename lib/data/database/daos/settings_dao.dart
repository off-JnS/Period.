import 'package:drift/drift.dart';

import '../../../domain/models/app_preferences.dart';
import '../../../domain/models/cycle_mode.dart';
import '../../../domain/models/profile.dart';
import '../../../domain/models/reminder_settings.dart';
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

  /// `true` when the app asks for Face ID, Touch ID or the passcode to open.
  static const appLock = 'app_lock';

  /// `true` when she wants a reminder before the estimated window.
  static const reminderPeriod = 'reminder_period';

  /// Days before the window for that reminder, as a decimal integer.
  static const reminderDaysBefore = 'reminder_days_before';

  /// `true` when she wants a daily reminder to log.
  static const reminderDaily = 'reminder_daily';

  /// The reminder time as `HH:MM`, 24-hour.
  static const reminderTime = 'reminder_time';

  /// `true` when the home-screen widget may show details.
  static const widgetDetailed = 'widget_detailed';

  /// Her birth year, as a decimal integer.
  static const profileBirthYear = 'profile_birth_year';

  /// The cycle length she says is usual, in days.
  static const profileCycleLength = 'profile_cycle_length';

  /// The period length she says is usual, in days.
  static const profilePeriodLength = 'profile_period_length';

  /// Her [ContraceptionMethod], by enum name.
  static const profileContraception = 'profile_contraception';

  /// Her [KnownCondition]s, by enum name, comma-separated.
  static const profileConditions = 'profile_conditions';
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

  /// Whether the app lock is on. Off unless she turned it on.
  Future<bool> appLockEnabled() async =>
      (await _values())[SettingKeys.appLock] == 'true';

  /// Turns the app lock on or off.
  Future<void> saveAppLockEnabled({required bool enabled}) =>
      _put(SettingKeys.appLock, '$enabled');

  /// The stored reminder settings, with defaults for anything not stored or
  /// not understood. Out-of-range numbers fall back rather than being trusted.
  Future<ReminderSettings> reminderSettings() async {
    final values = await _values();
    const defaults = ReminderSettings();

    final days = int.tryParse(values[SettingKeys.reminderDaysBefore] ?? '');
    final time = RegExp(r'^(\d{2}):(\d{2})$')
        .firstMatch(values[SettingKeys.reminderTime] ?? '');
    final hour = time == null ? null : int.parse(time.group(1)!);
    final minute = time == null ? null : int.parse(time.group(2)!);
    final timeValid =
        hour != null && minute != null && hour < 24 && minute < 60;

    return ReminderSettings(
      periodComing: values[SettingKeys.reminderPeriod] == 'true',
      daysBefore:
          days != null &&
              days >= ReminderSettings.minDaysBefore &&
              days <= ReminderSettings.maxDaysBefore
          ? days
          : defaults.daysBefore,
      dailyLog: values[SettingKeys.reminderDaily] == 'true',
      hour: timeValid ? hour : defaults.hour,
      minute: timeValid ? minute : defaults.minute,
    );
  }

  /// Stores [settings], replacing whatever was there.
  Future<void> saveReminderSettings(ReminderSettings settings) async {
    String two(int n) => n.toString().padLeft(2, '0');
    await transaction(() async {
      await _put(SettingKeys.reminderPeriod, '${settings.periodComing}');
      await _put(SettingKeys.reminderDaysBefore, '${settings.daysBefore}');
      await _put(SettingKeys.reminderDaily, '${settings.dailyLog}');
      await _put(
        SettingKeys.reminderTime,
        '${two(settings.hour)}:${two(settings.minute)}',
      );
    });
  }

  /// Whether the widget may show more than the day number. Off unless she
  /// turned it on.
  Future<bool> widgetDetailed() async =>
      (await _values())[SettingKeys.widgetDetailed] == 'true';

  /// Turns the widget's details on or off.
  Future<void> saveWidgetDetailed({required bool detailed}) =>
      _put(SettingKeys.widgetDetailed, '$detailed');

  /// What she has said about herself. Anything missing, out of range or not
  /// understood reads as unsaid rather than being trusted or thrown over.
  Future<Profile> profile({required int currentYear}) async {
    final values = await _values();

    int? within(String key, int min, int max) {
      final value = int.tryParse(values[key] ?? '');
      return value != null && value >= min && value <= max ? value : null;
    }

    final conditionNames = KnownCondition.values.asNameMap();
    return Profile(
      birthYear: within(
        SettingKeys.profileBirthYear,
        currentYear - Profile.maxAge,
        currentYear - Profile.minAge,
      ),
      usualCycleLength: within(
        SettingKeys.profileCycleLength,
        Profile.minCycleLength,
        Profile.maxCycleLength,
      ),
      usualPeriodLength: within(
        SettingKeys.profilePeriodLength,
        Profile.minPeriodLength,
        Profile.maxPeriodLength,
      ),
      contraception: ContraceptionMethod.values
          .asNameMap()[values[SettingKeys.profileContraception]],
      conditions: {
        for (final name
            in (values[SettingKeys.profileConditions] ?? '').split(','))
          ?conditionNames[name],
      },
    );
  }

  /// Stores [profile], replacing whatever was there. A field she cleared is
  /// deleted rather than kept as an empty value.
  Future<void> saveProfile(Profile profile) async {
    Future<void> putOrClear(String key, Object? value) => value == null
        ? _clear(key)
        : _put(key, '$value');

    await transaction(() async {
      await putOrClear(SettingKeys.profileBirthYear, profile.birthYear);
      await putOrClear(
        SettingKeys.profileCycleLength,
        profile.usualCycleLength,
      );
      await putOrClear(
        SettingKeys.profilePeriodLength,
        profile.usualPeriodLength,
      );
      await putOrClear(
        SettingKeys.profileContraception,
        profile.contraception?.name,
      );
      await putOrClear(
        SettingKeys.profileConditions,
        profile.conditions.isEmpty
            ? null
            : [
                for (final condition in KnownCondition.values)
                  if (profile.conditions.contains(condition)) condition.name,
              ].join(','),
      );
    });
  }

  Future<void> _clear(String key) => (delete(
    appSettings,
  )..where((row) => row.settingKey.equals(key))).go();

  Future<Map<String, String>> _values() async {
    final rows = await select(appSettings).get();
    return {for (final row in rows) row.settingKey: row.settingValue};
  }

  Future<void> _put(String key, String value) => into(appSettings).insert(
    AppSettingsCompanion.insert(settingKey: key, settingValue: value),
    mode: InsertMode.replace,
  );
}
