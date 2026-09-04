import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';

void main() => runApp(const PeriodApp());

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
      home: const _TodayPlaceholder(),
    );
  }
}

class _TodayPlaceholder extends StatelessWidget {
  const _TodayPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayTitle)),
      body: Center(child: Text(l10n.nothingLoggedYet)),
    );
  }
}
