import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/widgets.dart';

/// Golden tests for Settings. Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    CycleSettings settings,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      SettingsScreen(settings: settings, onChanged: (_) {}),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
    );
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_$name.png'),
    );
  }

  testWidgets('the defaults', (tester) async {
    await expectGolden(tester, const CycleSettings(), 'defaults');
  });

  testWidgets('the fertile window opted in', (tester) async {
    await expectGolden(
      tester,
      const CycleSettings(fertileWindowOptedIn: true),
      'fertile_window',
    );
  });

  testWidgets('perimenopause with estimates turned back on', (tester) async {
    await expectGolden(
      tester,
      const CycleSettings(
        mode: CycleMode.perimenopause,
        predictionsOptedIn: true,
      ),
      'perimenopause',
    );
  });

  testWidgets('pregnancy', (tester) async {
    await expectGolden(
      tester,
      const CycleSettings(mode: CycleMode.pregnancy),
      'pregnancy',
    );
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(
      tester,
      const CycleSettings(),
      'dark',
      brightness: Brightness.dark,
    );
  });

  testWidgets('German', (tester) async {
    await expectGolden(
      tester,
      const CycleSettings(mode: CycleMode.perimenopause),
      'german',
      locale: const Locale('de'),
    );
  });

  testWidgets('at 200% text size', (tester) async {
    await expectGolden(
      tester,
      const CycleSettings(),
      'large_text',
      textScale: 2,
    );
  });

  testWidgets('the whole screen, with dark and German chosen', (tester) async {
    await pumpApp(
      tester,
      SettingsScreen(
        settings: const CycleSettings(),
        onChanged: (_) {},
        preferences: const AppPreferences(
          appearance: AppearanceChoice.dark,
          language: LanguageChoice.german,
        ),
        onPreferencesChanged: (_) {},
        lockEnabled: true,
        onLockChanged: (_) {},
        reminders: const ReminderSettings(
          periodComing: true,
          dailyLog: true,
          hour: 20,
          minute: 30,
        ),
        onRemindersChanged: (_) {},
        onEraseEverything: () {},
      ),
      locale: const Locale('de'),
      brightness: Brightness.dark,
      // Tall enough to show every group at once.
      surface: const Size(400, 2200),
    );
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_whole_dark_german.png'),
    );
  });
}
