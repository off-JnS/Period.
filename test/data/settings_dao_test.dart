import 'package:period/data/database/daos/settings_dao.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:test/test.dart';

import '../support/database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = aDatabase());
  tearDown(() => database.close());

  Future<void> storeRaw(String key, String value) => database
      .into(database.appSettings)
      .insert(
        AppSettingsCompanion.insert(settingKey: key, settingValue: value),
      );

  test('nothing stored reads as the defaults', () async {
    expect(await database.settingsDao.cycleSettings(), const CycleSettings());
  });

  test('every mode round-trips', () async {
    for (final mode in CycleMode.values) {
      final settings = CycleSettings(mode: mode);
      await database.settingsDao.saveCycleSettings(settings);
      expect(await database.settingsDao.cycleSettings(), settings);
    }
  });

  test('both opt-ins round-trip, on and back off', () async {
    const on = CycleSettings(
      mode: CycleMode.perimenopause,
      predictionsOptedIn: true,
      fertileWindowOptedIn: true,
    );
    await database.settingsDao.saveCycleSettings(on);
    expect(await database.settingsDao.cycleSettings(), on);

    // Turning something off is a write, not a no-op.
    const off = CycleSettings(mode: CycleMode.perimenopause);
    await database.settingsDao.saveCycleSettings(off);
    expect(await database.settingsDao.cycleSettings(), off);
  });

  test('saving again replaces rather than duplicating rows', () async {
    await database.settingsDao.saveCycleSettings(const CycleSettings());
    await database.settingsDao.saveCycleSettings(
      const CycleSettings(mode: CycleMode.pregnancy),
    );
    final rows = await database.select(database.appSettings).get();
    expect(rows.map((row) => row.settingKey).toSet(), hasLength(rows.length));
  });

  test('a mode this build does not know reads as natural', () async {
    // Written by a newer version, then the app was downgraded. Failing to
    // start over a setting would lock her out of her own data.
    await storeRaw(SettingKeys.cycleMode, 'someFutureMode');
    expect(
      (await database.settingsDao.cycleSettings()).mode,
      CycleMode.natural,
    );
  });

  test('an unreadable opt-in reads as off', () async {
    await storeRaw(SettingKeys.fertileWindowOptedIn, 'yes please');
    await storeRaw(SettingKeys.predictionsOptedIn, '');
    final settings = await database.settingsDao.cycleSettings();
    expect(settings.fertileWindowOptedIn, isFalse);
    expect(settings.predictionsOptedIn, isFalse);
  });

  test('settings unknown to this build are left alone', () async {
    await storeRaw('some_future_setting', 'kept');
    await database.settingsDao.saveCycleSettings(const CycleSettings());
    final rows = await database.select(database.appSettings).get();
    expect(
      rows.where((row) => row.settingKey == 'some_future_setting').single,
      isA<SettingRow>().having((row) => row.settingValue, 'value', 'kept'),
    );
  });

  group('app preferences', () {
    test('nothing stored follows the device', () async {
      expect(
        await database.settingsDao.appPreferences(),
        const AppPreferences(),
      );
    });

    test('every appearance and language round-trips', () async {
      for (final appearance in AppearanceChoice.values) {
        for (final language in LanguageChoice.values) {
          final preferences = AppPreferences(
            appearance: appearance,
            language: language,
          );
          await database.settingsDao.saveAppPreferences(preferences);
          expect(await database.settingsDao.appPreferences(), preferences);
        }
      }
    });

    test('values this build does not know fall back to the device', () async {
      await storeRaw(SettingKeys.appearance, 'sepia');
      await storeRaw(SettingKeys.language, 'klingon');
      expect(
        await database.settingsDao.appPreferences(),
        const AppPreferences(),
      );
    });

    test('saving preferences leaves the cycle settings alone', () async {
      const cycle = CycleSettings(
        mode: CycleMode.pregnancy,
        fertileWindowOptedIn: true,
      );
      await database.settingsDao.saveCycleSettings(cycle);
      await database.settingsDao.saveAppPreferences(
        const AppPreferences(appearance: AppearanceChoice.dark),
      );
      expect(await database.settingsDao.cycleSettings(), cycle);
    });

    test('saving cycle settings leaves the preferences alone', () async {
      const preferences = AppPreferences(language: LanguageChoice.german);
      await database.settingsDao.saveAppPreferences(preferences);
      await database.settingsDao.saveCycleSettings(const CycleSettings());
      expect(await database.settingsDao.appPreferences(), preferences);
    });
  });

  group('app lock', () {
    test('is off until turned on', () async {
      expect(await database.settingsDao.appLockEnabled(), isFalse);
    });

    test('round-trips on and off', () async {
      await database.settingsDao.saveAppLockEnabled(enabled: true);
      expect(await database.settingsDao.appLockEnabled(), isTrue);
      await database.settingsDao.saveAppLockEnabled(enabled: false);
      expect(await database.settingsDao.appLockEnabled(), isFalse);
    });

    test('an unreadable value reads as off', () async {
      await storeRaw(SettingKeys.appLock, 'maybe');
      expect(await database.settingsDao.appLockEnabled(), isFalse);
    });
  });

  group('reminders', () {
    test('are off until turned on, at 9:00, two days ahead', () async {
      expect(
        await database.settingsDao.reminderSettings(),
        const ReminderSettings(),
      );
    });

    test('round-trip', () async {
      const chosen = ReminderSettings(
        periodComing: true,
        daysBefore: 4,
        dailyLog: true,
        hour: 7,
        minute: 5,
      );
      await database.settingsDao.saveReminderSettings(chosen);
      expect(await database.settingsDao.reminderSettings(), chosen);
    });

    test('an out-of-range lead time falls back to the default', () async {
      await storeRaw(SettingKeys.reminderDaysBefore, '12');
      expect(
        (await database.settingsDao.reminderSettings()).daysBefore,
        ReminderSettings.defaultDaysBefore,
      );
    });

    test('a malformed or impossible time falls back to 9:00', () async {
      for (final raw in ['7:5', '25:00', '09:60', 'noon', '']) {
        await database.settingsDao.saveReminderSettings(
          const ReminderSettings(),
        );
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                settingKey: SettingKeys.reminderTime,
                settingValue: raw,
              ),
            );
        final read = await database.settingsDao.reminderSettings();
        expect((read.hour, read.minute), (9, 0), reason: raw);
      }
    });
  });

  group('profile', () {
    Future<Profile> read() => database.settingsDao.profile(currentYear: 2026);

    test('nothing stored reads as an empty profile', () async {
      expect(await read(), const Profile());
    });

    test('a full profile round-trips', () async {
      const profile = Profile(
        birthYear: 1998,
        usualCycleLength: 31,
        usualPeriodLength: 5,
        contraception: ContraceptionMethod.copperIud,
        conditions: {KnownCondition.pcos, KnownCondition.thyroid},
      );
      await database.settingsDao.saveProfile(profile);
      expect(await read(), profile);
    });

    test('every method and condition round-trips', () async {
      for (final method in ContraceptionMethod.values) {
        await database.settingsDao.saveProfile(Profile(contraception: method));
        expect((await read()).contraception, method);
      }
      await database.settingsDao.saveProfile(
        Profile(conditions: KnownCondition.values.toSet()),
      );
      expect((await read()).conditions, KnownCondition.values.toSet());
    });

    test('clearing a field deletes it', () async {
      await database.settingsDao.saveProfile(
        const Profile(birthYear: 1990, conditions: {KnownCondition.pmdd}),
      );
      await database.settingsDao.saveProfile(const Profile());
      expect(await read(), const Profile());
      final keys = (await database.select(database.appSettings).get()).map(
        (row) => row.settingKey,
      );
      expect(keys.where((key) => key.startsWith('profile_')), isEmpty);
    });

    test('values out of range or not understood read as unsaid', () async {
      await storeRaw(SettingKeys.profileBirthYear, '2025');
      await storeRaw(SettingKeys.profileCycleLength, '200');
      await storeRaw(SettingKeys.profilePeriodLength, 'five');
      await storeRaw(SettingKeys.profileContraception, 'tomorrowPill');
      await storeRaw(SettingKeys.profileConditions, 'pcos,,somethingNew');
      expect(await read(), const Profile(conditions: {KnownCondition.pcos}));
    });

    test('does not disturb the other settings', () async {
      const settings = CycleSettings(mode: CycleMode.pregnancy);
      await database.settingsDao.saveCycleSettings(settings);
      await database.settingsDao.saveProfile(const Profile(birthYear: 1990));
      await database.settingsDao.saveProfile(const Profile());
      expect(await database.settingsDao.cycleSettings(), settings);
    });
  });
}
