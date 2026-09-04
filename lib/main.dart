import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain/logic/period_prediction.dart';
import 'l10n/app_localizations.dart';
import 'presentation/today/today_screen.dart';

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
      home: const TodayScreen(
        // Not yet wired to the database: this is the state of a fresh install,
        // with nothing logged. Reading real entries needs a way to log them
        // first, which is the next slice.
        data: TodayViewData(
          prediction: NotEnoughCycles(have: 0, need: cyclesNeededToPredict),
        ),
      ),
    );
  }
}
