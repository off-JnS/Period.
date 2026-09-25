import 'package:flutter/material.dart';

import 'data/database/database.dart';
import 'data/app_lock/device_authenticator.dart';
import 'data/database/open_database.dart';
import 'data/reminders/reminder_scheduler.dart';
import 'data/widget/widget_bridge.dart';
import 'data/database_key_store.dart';
import 'data/demo_data.dart';
import 'data/erase_all_data.dart';
import 'data/system_clock.dart';
import 'domain/models/app_preferences.dart';
import 'l10n/app_localizations.dart';
import 'presentation/home_shell.dart';
import 'presentation/lock/app_lock.dart';
import 'presentation/reminders/reminder_sync.dart';
import 'presentation/widget/widget_sync.dart';
import 'presentation/preferences_mapping.dart';

Future<void> main() async {
  // The database is opened from inside the app rather than here, so that a
  // failure to open it can be reported in the user's own language instead of on
  // a grey screen.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PeriodApp());
}

/// The application root.
///
/// Owns the one database connection and hands it down. There is no dependency
/// injection framework: section 6 lists `flutter_riverpod` as allowed but not
/// as required, and a single connection passed by constructor is legible
/// without one. When a second screen needs it, that is the moment to revisit.
class PeriodApp extends StatefulWidget {
  /// Creates the application root.
  const PeriodApp({super.key});

  @override
  State<PeriodApp> createState() => _PeriodAppState();
}

class _PeriodAppState extends State<PeriodApp> {
  /// The open database, or null while opening.
  AppDatabase? _database;

  /// Why the database could not be opened.
  ///
  /// There is no unencrypted fallback and there must not be one. If the store
  /// cannot be opened as an encrypted store, the app says so and stops, rather
  /// than appearing to save entries it is not saving or saving them in the
  /// clear.
  Object? _error;

  /// Appearance and language. The device's choices until the stored ones are
  /// read, which happens before the first screen with her data is shown.
  AppPreferences _preferences = const AppPreferences();

  /// The optional app lock, once the database says whether it is on. Until
  /// then only the loading screen shows, which holds nothing of hers.
  AppLock? _lock;

  /// Keeps reminders scheduled; created with the database it reads.
  ReminderSync? _reminders;

  /// Keeps the home-screen widget's snapshot current.
  WidgetSync? _widget;

  final WidgetBridge _widgetBridge = const MethodChannelWidgetBridge();

  final DatabaseKeyStore _keyStore = SecureDatabaseKeyStore();
  final ReminderScheduler _scheduler = LocalNotificationsReminderScheduler();

  /// Shows the one message that has to survive the whole app being rebuilt:
  /// that everything was deleted.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// Deletes everything and starts again as a fresh install.
  ///
  /// Every screen is taken down first, so nothing reads the database while it
  /// is closed and deleted. If deletion fails part-way, the file and its key
  /// are still intact (see [eraseAllData]) and the app simply reopens them.
  Future<void> _eraseEverything(String done, String failed) async {
    final database = _database;
    if (database == null) return;
    final lock = _lock;

    setState(() {
      _database = null;
      _lock = null;
      _reminders = null;
      _widget = null;
    });
    // Disposed after the frame that stops the lock gate listening to it.
    WidgetsBinding.instance.addPostFrameCallback((_) => lock?.dispose());

    var erased = false;
    try {
      await eraseAllData(
        database: database,
        directory: await databaseDirectory(),
        keyStore: _keyStore,
        reminders: _scheduler,
        widget: _widgetBridge,
      );
      erased = true;
    } on Object {
      erased = false;
    }

    if (!mounted) return;
    if (erased) setState(() => _preferences = const AppPreferences());
    await _open();
    _messenger.currentState?.showSnackBar(
      SnackBar(content: Text(erased ? done : failed)),
    );
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final database = await openEncryptedDatabase(keyStore: _keyStore);
      if (demoDataRequested &&
          (await database.logDao.allPeriodStarts()).isEmpty) {
        await seedDemoData(database, const SystemClock().today());
      }
      // Read before the database is handed to the screens, so the first
      // screen already has her theme and language rather than switching
      // under her a moment later.
      final preferences = await database.settingsDao.appPreferences();
      final lock = AppLock(
        authenticator: LocalAuthDeviceAuthenticator(),
        enabled: await database.settingsDao.appLockEnabled(),
        save: database.settingsDao.saveAppLockEnabled,
      );
      if (!mounted) {
        lock.dispose();
        await database.close();
        return;
      }
      setState(() {
        _preferences = preferences;
        _lock = lock;
        _reminders = ReminderSync(
          logDao: database.logDao,
          settingsDao: database.settingsDao,
          scheduler: _scheduler,
          clock: const SystemClock(),
        );
        _widget = WidgetSync(
          logDao: database.logDao,
          settingsDao: database.settingsDao,
          bridge: _widgetBridge,
          clock: const SystemClock(),
          lockEnabled: () => lock.enabled,
        );
        _database = database;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _lock?.dispose();
    _database?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return periodMaterialApp(
      preferences: _preferences,
      lock: _lock,
      messengerKey: _messenger,
      home: Builder(
        builder: (context) {
          if (_error != null) return const _CouldNotOpen();
          final database = _database;
          if (database == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          return HomeShell(
            logDao: database.logDao,
            settingsDao: database.settingsDao,
            clock: const SystemClock(),
            appLock: _lock,
            reminderSync: _reminders,
            widgetSync: _widget,
            onEraseEverything: _eraseEverything,
            // Applied at once, from the Settings screen: the whole app
            // re-themes or re-translates in place, on the same tab.
            onPreferencesChanged: (preferences) =>
                setState(() => _preferences = preferences),
          );
        },
      ),
    );
  }
}

/// Shown when the encrypted database could not be opened.
class _CouldNotOpen extends StatelessWidget {
  const _CouldNotOpen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.couldNotOpenData,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
