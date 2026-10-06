import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/l10n/app_localizations.dart';
import 'package:period/presentation/preferences_mapping.dart';

void main() {
  const supported = AppLocalizations.supportedLocales;

  group('resolveDeviceLocale', () {
    test('uses the device language when the app has it', () {
      expect(
        resolveDeviceLocale([const Locale('de', 'AT')], supported),
        const Locale('de'),
      );
      expect(
        resolveDeviceLocale([const Locale('en', 'GB')], supported),
        const Locale('en'),
      );
    });

    test('falls back to English, not German, for other languages', () {
      expect(
        resolveDeviceLocale([const Locale('fr')], supported),
        const Locale('en'),
      );
    });

    test('tries the device languages in order of preference', () {
      expect(
        resolveDeviceLocale([
          const Locale('fr'),
          const Locale('de'),
          const Locale('en'),
        ], supported),
        const Locale('de'),
      );
    });

    test('falls back to English when the device reports nothing', () {
      expect(resolveDeviceLocale(null, supported), const Locale('en'));
      expect(resolveDeviceLocale([], supported), const Locale('en'));
    });
  });

  test('every appearance maps to its theme mode', () {
    expect(themeModeFor(AppearanceChoice.system), ThemeMode.system);
    expect(themeModeFor(AppearanceChoice.light), ThemeMode.light);
    expect(themeModeFor(AppearanceChoice.dark), ThemeMode.dark);
  });

  test('a chosen language is forced, the device language is not', () {
    expect(localeFor(LanguageChoice.system), isNull);
    expect(localeFor(LanguageChoice.german), const Locale('de'));
    expect(localeFor(LanguageChoice.english), const Locale('en'));
  });

  group('the app', () {
    late String shown;
    late Brightness brightness;

    Widget probe() => Builder(
      builder: (context) {
        shown = AppLocalizations.of(context).todayTitle;
        brightness = Theme.of(context).brightness;
        return const SizedBox();
      },
    );

    testWidgets('dark is dark even on a light device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        periodMaterialApp(
          preferences: const AppPreferences(appearance: AppearanceChoice.dark),
          home: probe(),
        ),
      );
      expect(brightness, Brightness.dark);
    });

    testWidgets('light is light even on a dark device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        periodMaterialApp(
          preferences: const AppPreferences(appearance: AppearanceChoice.light),
          home: probe(),
        ),
      );
      expect(brightness, Brightness.light);
    });

    testWidgets('automatic follows the device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        periodMaterialApp(preferences: const AppPreferences(), home: probe()),
      );
      expect(brightness, Brightness.dark);
    });

    testWidgets('a chosen language wins over the device', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        periodMaterialApp(
          preferences: const AppPreferences(language: LanguageChoice.german),
          home: probe(),
        ),
      );
      await tester.pumpAndSettle();
      expect(shown, 'Heute');
    });

    testWidgets('a French device gets English, not German', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        periodMaterialApp(preferences: const AppPreferences(), home: probe()),
      );
      await tester.pumpAndSettle();
      expect(shown, 'Today');
    });
  });
}
