import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_preferences.freezed.dart';

/// Light or dark, or whatever the device is set to.
enum AppearanceChoice {
  /// Follow the device, switching with it at sunset if it does.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// Which language the app speaks.
enum LanguageChoice {
  /// The device's language when the app has it, English otherwise.
  system,

  /// German, whatever the device is set to.
  german,

  /// English, whatever the device is set to.
  english;

  /// The ISO 639-1 code, or null to follow the device.
  String? get languageCode => switch (this) {
    LanguageChoice.system => null,
    LanguageChoice.german => 'de',
    LanguageChoice.english => 'en',
  };
}

/// How the app looks and which language it uses.
///
/// Nothing here touches cycle logic. It lives in the domain only because it is
/// stored alongside the cycle settings and has to be describable without
/// Flutter; the presentation layer maps it to a theme mode and a locale.
@freezed
abstract class AppPreferences with _$AppPreferences {
  const factory AppPreferences({
    /// Light, dark, or the device's choice.
    @Default(AppearanceChoice.system) AppearanceChoice appearance,

    /// The app's language.
    @Default(LanguageChoice.system) LanguageChoice language,
  }) = _AppPreferences;
}
