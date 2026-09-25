import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/models/app_preferences.dart';
import '../l10n/app_localizations.dart';
import 'lock/app_lock.dart';
import 'lock/lock_gate.dart';
import 'theme.dart';

/// The Flutter theme mode for [choice].
ThemeMode themeModeFor(AppearanceChoice choice) => switch (choice) {
  AppearanceChoice.system => ThemeMode.system,
  AppearanceChoice.light => ThemeMode.light,
  AppearanceChoice.dark => ThemeMode.dark,
};

/// The locale to force for [choice], or null to follow the device.
Locale? localeFor(LanguageChoice choice) => switch (choice.languageCode) {
  final code? => Locale(code),
  null => null,
};

/// Picks the app language when following the device.
///
/// Flutter's default falls back to the *first* supported locale, which is
/// German because the list is alphabetical -- so a phone set to French would
/// get German. English is the better guess for someone the app has no
/// translation for, so that is the fallback here.
///
/// The device's preferred languages are tried in order, so someone with
/// "French, then German" set gets German rather than English.
Locale resolveDeviceLocale(
  List<Locale>? preferred,
  Iterable<Locale> supported,
) {
  for (final locale in preferred ?? const <Locale>[]) {
    for (final candidate in supported) {
      if (candidate.languageCode == locale.languageCode) return candidate;
    }
  }
  return supported.firstWhere(
    (locale) => locale.languageCode == 'en',
    orElse: () => supported.first,
  );
}

/// The app's [MaterialApp], themed and translated per [preferences].
///
/// Separate from `main.dart` so a test can check that a stored preference
/// really changes the theme and language, through the same code the app runs.
///
/// With a [lock], everything the navigator shows sits under a [LockGate].
MaterialApp periodMaterialApp({
  required AppPreferences preferences,
  required Widget home,
  AppLock? lock,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  scaffoldMessengerKey: messengerKey,
  onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: localeFor(preferences.language),
  localeListResolutionCallback: (preferred, supported) =>
      resolveDeviceLocale(preferred, supported),
  theme: lightTheme(),
  darkTheme: darkTheme(),
  themeMode: themeModeFor(preferences.appearance),
  builder: lock == null
      ? null
      : (context, child) =>
            LockGate(lock: lock, child: child ?? const SizedBox()),
  home: home,
);
