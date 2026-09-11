import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/database.dart';
import 'data/database/open_database.dart';
import 'data/reminders.dart';
import 'data/system_clock.dart';
import 'l10n/app_localizations.dart';
import 'presentation/app_shell.dart';
import 'presentation/lock/lock_gate.dart';
import 'presentation/providers.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened once, here, rather than lazily inside a provider: it is async and
  // touches the filesystem and the keystore, and a failure to decrypt should
  // stop the app rather than surface as a broken screen.
  final opened = await openEncryptedDatabase();

  final reminders = await _startReminders(opened.database);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(opened.database),
        documentsDirectoryProvider.overrideWithValue(opened.documents),
        remindersProvider.overrideWithValue(reminders),
      ],
      child: const PeriodApp(),
    ),
  );
}

/// Sets up section 9's log reminder and puts back whatever she asked for.
///
/// Rescheduled on every start rather than only when she changes it, because
/// several things silently drop what is pending and none of them tell the app:
/// an Android reboot before the boot receiver runs, a restore from a backup
/// that brought a different schedule, a locale change that leaves the pending
/// notification written in the old language, and the operating system clearing
/// them for its own reasons.
///
/// Failure here never stops the app. A missing reminder is a small loss; a
/// health app that will not open because a notification could not be scheduled
/// is a much larger one, and this runs before the first frame.
Future<Reminders> _startReminders(AppDatabase database) async {
  final reminders = LocalNotificationReminders();

  try {
    // Resolved from the device rather than assumed, because this runs before
    // there is a widget tree to read a locale from and the text it picks is
    // what she will actually see on her lock screen. Defaulting to English here
    // would leave a German user with an English notification until the next
    // time she opened settings.
    final l10n = await AppLocalizations.delegate.load(_deviceLocale());
    await reminders.initialize(
      channelName: l10n.reminderChannelName,
      channelDescription: l10n.reminderChannelDescription,
    );

    final stored = await database.settingsDao.readSettings();
    const clock = SystemClock();
    await reminders.applySchedule(
      stored.reminder,
      today: clock.today(),
      now: clock.timeOfDay(),
      title: l10n.reminderNotificationTitle,
      body: l10n.reminderNotificationBody,
    );
  } on Object {
    // A refused permission, a platform that cannot schedule, a stored mode this
    // build cannot read. None of them is a reason not to open the app.
  }

  return reminders;
}

/// The first locale the device asks for that this app actually has.
///
/// Falls back to the first supported locale, which is what [MaterialApp] does
/// with an unsupported one -- so the notification and the app agree rather than
/// disagreeing in a way only a German speaker would notice.
Locale _deviceLocale() {
  for (final locale in WidgetsBinding.instance.platformDispatcher.locales) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
  }
  return AppLocalizations.supportedLocales.first;
}

/// The application root.
///
/// Deliberately thin: localisation, theme, and the shell that owns navigation.
/// Everything a screen needs comes from providers rather than from here.
class PeriodApp extends StatelessWidget {
  /// Creates the application root.
  const PeriodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Both appearances, from the one place that defines them, so a golden
      // renders what the app renders. themeMode is left at its default, which
      // follows the device: there is no in-app appearance switch, because that
      // would be a second place to change a setting the system already owns.
      //
      // Until this was here the app was light in every condition, while six
      // dark goldens rendered a theme it never built.
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      // The gate, not the shell. While locked it replaces the app rather
      // than covering it, so nothing of hers is built behind the lock.
      home: const LockGate(child: AppShell()),
    );
  }
}
