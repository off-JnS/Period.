import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import '../data_error.dart';
import '../providers.dart';
import 'settings_screen.dart';

/// The settings screen connected to the database.
class SettingsPage extends ConsumerWidget {
  /// Creates the page.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);

    return settings.when(
      loading: () =>
          _frame(l10n, const Center(child: CircularProgressIndicator())),
      // Reached when the stored mode is one this build cannot read. Showing the
      // picker with a guessed selection would be worse than showing nothing:
      // the user would see a mode she never chose and might save over the one
      // she did.
      error: (error, stack) => _frame(
        l10n,
        DataErrorPanel(onRetry: () => ref.invalidate(settingsProvider)),
      ),
      data: (stored) => SettingsScreen(
        data: SettingsViewData(
          cycle: stored.cycle,
          fertileWindowOptedIn: stored.fertileWindowOptedIn,
        ),
        onModeChanged: (mode) => _saveCycle(
          ref,
          // The opt-in belongs to perimenopause. Carrying it across a mode
          // change would leave it silently set, ready to turn estimates on
          // again the moment she came back -- so it is dropped on the way out.
          mode == CycleMode.perimenopause
              ? stored.cycle.copyWith(mode: mode)
              : CycleSettings(mode: mode),
        ),
        onPredictionsOptInChanged: ({required optedIn}) =>
            _saveCycle(ref, stored.cycle.copyWith(predictionsOptedIn: optedIn)),
        onFertileWindowChanged: ({required optedIn}) async {
          await ref
              .read(databaseProvider)
              .settingsDao
              .writeFertileWindowOptIn(optedIn: optedIn);
          ref.invalidate(settingsProvider);
        },
        onDeleteEverything: () => _deleteEverything(context, ref),
      ),
    );
  }

  Widget _frame(AppLocalizations l10n, Widget child) => Scaffold(
    appBar: AppBar(title: Text(l10n.settingsTitle)),
    body: child,
  );

  Future<void> _saveCycle(WidgetRef ref, CycleSettings value) async {
    await ref.read(databaseProvider).settingsDao.writeCycleSettings(value);
    // One invalidation refreshes the mode here and the estimate on every other
    // screen together: nothing derived is stored, so there is no cache to keep
    // in step (section 4).
    ref.invalidate(settingsProvider);
  }

  Future<void> _deleteEverything(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(databaseProvider).logDao.deleteEverything();

    // Everything, including the settings rows -- so the app comes back as a
    // fresh install, which is what the confirmation promised and what someone
    // deleting under pressure needs it to mean.
    ref
      ..invalidate(settingsProvider)
      ..invalidate(periodStartsProvider)
      ..invalidate(dayEntryProvider)
      ..invalidate(loggedDaysProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.everythingDeleted)));
  }
}
