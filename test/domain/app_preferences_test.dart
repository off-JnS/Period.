import 'package:period/domain/models/app_preferences.dart';
import 'package:test/test.dart';

void main() {
  test('follows the device by default', () {
    const preferences = AppPreferences();
    expect(preferences.appearance, AppearanceChoice.system);
    expect(preferences.language, LanguageChoice.system);
  });

  test('language codes are the two the app is translated into', () {
    expect(LanguageChoice.system.languageCode, isNull);
    expect(LanguageChoice.german.languageCode, 'de');
    expect(LanguageChoice.english.languageCode, 'en');
  });

  test('every language choice is accounted for', () {
    // Adding a language without a code would silently follow the device.
    expect(
      LanguageChoice.values.where((choice) => choice.languageCode == null),
      [LanguageChoice.system],
    );
  });
}
