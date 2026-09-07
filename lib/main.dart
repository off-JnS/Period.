import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/open_database.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers.dart';
import 'presentation/today/today_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened once, here, rather than lazily inside a provider: it is async and
  // touches the filesystem and the keystore, and a failure to decrypt should
  // stop the app rather than surface as a broken screen.
  final database = await openEncryptedDatabase();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const PeriodApp(),
    ),
  );
}

/// The application root.
///
/// Deliberately thin. This slice lays the foundation described in CLAUDE.md
/// sections 2 and 3 — the layer structure, `CycleDate` and `Clock` — so the only
/// screen here is a placeholder that proves the localisation pipeline generates
/// and resolves. The real Today screen arrives with the cycle logic it needs.
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
      theme: ThemeData(useMaterial3: true),
      home: const TodayPage(),
    );
  }
}
