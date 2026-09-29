import 'package:drift/drift.dart';

import '../../../domain/models/app_preferences.dart';
import '../../../domain/models/cycle_date.dart';
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

  /// `true` when she wants a pill reminder.
  static const reminderPill = 'reminder_pill';

  /// The pill reminder time as `HH:MM`, 24-hour.
  static const reminderPillTime = 'reminder_pill_time';

  /// Her [PillPack], by enum name.
  static const reminderPillPack = 'reminder_pill_pack';

  /// The first day of a pill pack, `YYYY-MM-DD`; empty for none.
  static const reminderPillPackStart = 'reminder_pill_pack_start';

  /// `true` when she wants ring reminders.
  static const reminderRing = 'reminder_ring';

  /// The day the current ring went in, `YYYY-MM-DD`; empty for none.
  static const reminderRingInserted = 'reminder_ring_inserted';

  /// `true` when she wants patch reminders.
  static const reminderPatch = 'reminder_patch';

  /// The day the current patch pack began, `YYYY-MM-DD`; empty for none.
  static const reminderPatchStarted = 'reminder_patch_started';

  /// `true` when she wants injection reminders.
  static const reminderInjection = 'reminder_injection';

  /// The day of her last injection, `YYYY-MM-DD`; empty for none.
  static const reminderInjectionLast = 'reminder_injection_last';

  /// Weeks between injections, as a decimal integer.
  static const reminderInjectionWeeks = 'reminder_injection_weeks';

  /// `true` when she wants IUD or implant reminders.
  static const reminderDevice = 'reminder_device';

  /// The day it should be replaced by, `YYYY-MM-DD`; empty for none.
  static const reminderDeviceReplaceBy = 'reminder_device_replace_by';

  /// Weeks ahead to be reminded, as a decimal integer.
  static const reminderDeviceWeeks = 'reminder_device_weeks';

  /// The time for the ring, patch, injection and device reminders, `HH:MM`.
  static const reminderMethodTime = 'reminder_method_time';

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

  /// `true` once she finished or skipped the first-launch introduction.
  static const onboardingDone = 'onboarding_done';
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

    int? number(String key, int min, int max) {
      final value = int.tryParse(values[key] ?? '');
      return value != null && value >= min && value <= max ? value : null;
    }

    (int, int)? time(String key) {
      final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(values[key] ?? '');
      if (match == null) return null;
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      return hour < 24 && minute < 60 ? (hour, minute) : null;
    }

    CycleDate? day(String key) {
      final value = values[key];
      if (value == null || value.isEmpty) return null;
      try {
        return CycleDate.parseIso8601(value);
      } on FormatException {
        return null;
      }
    }

    final cycleTime = time(SettingKeys.reminderTime);
    final pillTime = time(SettingKeys.reminderPillTime);
    final methodTime = time(SettingKeys.reminderMethodTime);
    final deviceWeeks = int.tryParse(
      values[SettingKeys.reminderDeviceWeeks] ?? '',
    );

    return ReminderSettings(
      periodComing: values[SettingKeys.reminderPeriod] == 'true',
      daysBefore:
          number(
            SettingKeys.reminderDaysBefore,
            ReminderSettings.minDaysBefore,
            ReminderSettings.maxDaysBefore,
          ) ??
          defaults.daysBefore,
      dailyLog: values[SettingKeys.reminderDaily] == 'true',
      hour: cycleTime?.$1 ?? defaults.hour,
      minute: cycleTime?.$2 ?? defaults.minute,
      pill: values[SettingKeys.reminderPill] == 'true',
      pillHour: pillTime?.$1 ?? defaults.pillHour,
      pillMinute: pillTime?.$2 ?? defaults.pillMinute,
      pillPack:
          PillPack.values.asNameMap()[values[SettingKeys.reminderPillPack]] ??
          defaults.pillPack,
      pillPackStart: day(SettingKeys.reminderPillPackStart),
      ring: values[SettingKeys.reminderRing] == 'true',
      ringInserted: day(SettingKeys.reminderRingInserted),
      patch: values[SettingKeys.reminderPatch] == 'true',
      patchStarted: day(SettingKeys.reminderPatchStarted),
      injection: values[SettingKeys.reminderInjection] == 'true',
      injectionLast: day(SettingKeys.reminderInjectionLast),
      injectionWeeks:
          number(
            SettingKeys.reminderInjectionWeeks,
            ReminderSettings.minInjectionWeeks,
            ReminderSettings.maxInjectionWeeks,
          ) ??
          defaults.injectionWeeks,
      device: values[SettingKeys.reminderDevice] == 'true',
      deviceReplaceBy: day(SettingKeys.reminderDeviceReplaceBy),
      deviceWeeksBefore:
          ReminderSettings.deviceWeeksOptions.contains(deviceWeeks)
          ? deviceWeeks!
          : defaults.deviceWeeksBefore,
      methodHour: methodTime?.$1 ?? defaults.methodHour,
      methodMinute: methodTime?.$2 ?? defaults.methodMinute,
    );
  }

  /// Stores [settings], replacing whatever was there.
  Future<void> saveReminderSettings(ReminderSettings settings) async {
    String two(int n) => n.toString().padLeft(2, '0');
    String time(int hour, int minute) => '${two(hour)}:${two(minute)}';
    String day(CycleDate? date) => date?.toIso8601() ?? '';
    await transaction(() async {
      await _put(SettingKeys.reminderPeriod, '${settings.periodComing}');
      await _put(SettingKeys.reminderDaysBefore, '${settings.daysBefore}');
      await _put(SettingKeys.reminderDaily, '${settings.dailyLog}');
      await _put(
        SettingKeys.reminderTime,
        time(settings.hour, settings.minute),
      );
      await _put(SettingKeys.reminderPill, '${settings.pill}');
      await _put(
        SettingKeys.reminderPillTime,
        time(settings.pillHour, settings.pillMinute),
      );
      await _put(SettingKeys.reminderPillPack, settings.pillPack.name);
      await _put(
        SettingKeys.reminderPillPackStart,
        day(settings.pillPackStart),
      );
      await _put(SettingKeys.reminderRing, '${settings.ring}');
      await _put(SettingKeys.reminderRingInserted, day(settings.ringInserted));
      await _put(SettingKeys.reminderPatch, '${settings.patch}');
      await _put(SettingKeys.reminderPatchStarted, day(settings.patchStarted));
      await _put(SettingKeys.reminderInjection, '${settings.injection}');
      await _put(
        SettingKeys.reminderInjectionLast,
        day(settings.injectionLast),
      );
      await _put(
        SettingKeys.reminderInjectionWeeks,
        '${settings.injectionWeeks}',
      );
      await _put(SettingKeys.reminderDevice, '${settings.device}');
      await _put(
        SettingKeys.reminderDeviceReplaceBy,
        day(settings.deviceReplaceBy),
      );
      await _put(
        SettingKeys.reminderDeviceWeeks,
        '${settings.deviceWeeksBefore}',
      );
      await _put(
        SettingKeys.reminderMethodTime,
        time(settings.methodHour, settings.methodMinute),
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

  /// Whether she has finished or skipped the first-launch introduction.
  Future<bool> onboardingDone() async =>
      (await _values())[SettingKeys.onboardingDone] == 'true';

  /// Records that the introduction is behind her, so it never shows again.
  Future<void> saveOnboardingDone() => _put(SettingKeys.onboardingDone, 'true');

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
        for (final name in (values[SettingKeys.profileConditions] ?? '').split(
          ',',
        ))
          ?conditionNames[name],
      },
    );
  }

  /// Stores [profile], replacing whatever was there. A field she cleared is
  /// deleted rather than kept as an empty value.
  Future<void> saveProfile(Profile profile) async {
    Future<void> putOrClear(String key, Object? value) =>
        value == null ? _clear(key) : _put(key, '$value');

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

  Future<void> _clear(String key) =>
      (delete(appSettings)..where((row) => row.settingKey.equals(key))).go();

  Future<Map<String, String>> _values() async {
    final rows = await select(appSettings).get();
    return {for (final row in rows) row.settingKey: row.settingValue};
  }

  Future<void> _put(String key, String value) => into(appSettings).insert(
    AppSettingsCompanion.insert(settingKey: key, settingValue: value),
    mode: InsertMode.replace,
  );
}
