import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/widgets.dart';

/// Golden tests for Settings. Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
///
/// The cycle mode moved to Profile; its states are in profile_golden_test.
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      const SettingsScreen(),
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
    await expectGolden(tester, 'defaults');
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(tester, 'dark', brightness: Brightness.dark);
  });

  testWidgets('German', (tester) async {
    await expectGolden(tester, 'german', locale: const Locale('de'));
  });

  testWidgets('at 200% text size', (tester) async {
    await expectGolden(tester, 'large_text', textScale: 2);
  });

  testWidgets('the whole screen, with dark and German chosen', (tester) async {
    await pumpApp(
      tester,
      SettingsScreen(
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
        onOpenReminders: () {},
        onEraseEverything: () {},
        widgetDetailed: false,
        onWidgetDetailedChanged: (_) {},
      ),
      locale: const Locale('de'),
      brightness: Brightness.dark,
      // Tall enough to show every group at once.
      surface: const Size(400, 1900),
    );
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_whole_dark_german.png'),
    );
  });
}
