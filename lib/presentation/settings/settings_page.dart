import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup/backup_document.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import '../data_error.dart';
import '../providers.dart';
import 'passphrase_dialog.dart';
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
        onExportBackup: () => _export(context, ref),
        onRestoreBackup: () => _restore(context, ref),
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

  /// Makes a backup and hands it to the share sheet.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final passphrase = await askForPassphrase(context, confirming: true);
    if (passphrase == null || !context.mounted) return;

    final today = ref.read(clockProvider).today();
    final transfer = ref.read(backupTransferProvider);
    final service = ref.read(backupServiceProvider);

    try {
      final file = await transfer.fileToWrite(_backupName(today));
      await service.exportTo(file, today: today, passphrase: passphrase);
      await transfer.send(file);
    } on Object {
      // No space, no permission, no share sheet. She needs to know it did not
      // happen; which of the three it was would not change what she does next.
      if (context.mounted) _say(context, l10n.backupFailed);
      return;
    }

    if (context.mounted) _say(context, l10n.backupCreated);
  }

  /// Restores from a backup she chooses, after confirming what that replaces.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final file = await ref.read(backupTransferProvider).choose();
    if (file == null || !context.mounted) return;

    // Asked before the passphrase, so she can back out without having typed
    // it, and so the consequence is on screen while she decides.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.replaceEverythingTitle),
        content: Text(l10n.replaceEverythingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.replaceAction),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    final passphrase = await askForPassphrase(context, confirming: false);
    if (passphrase == null || !context.mounted) return;

    try {
      await ref
          .read(backupServiceProvider)
          .importFrom(file, passphrase: passphrase);
    } on BackupException catch (error) {
      // Four separate messages, because they call for four different next
      // steps: retype it, pick another file, update the app, or give up on
      // this file. A single "import failed" would say none of that.
      if (context.mounted) _say(context, _messageFor(l10n, error.problem));
      return;
    }

    _refresh(ref);
    if (context.mounted) _say(context, l10n.backupRestored);
  }

  /// A name that sorts and says what it is. No clock time: section 3 keeps
  /// timestamps out of cycle data, and the hour is not hers to hand over.
  String _backupName(CycleDate today) => 'period-backup-${today.toIso8601()}';

  String _messageFor(AppLocalizations l10n, BackupProblem problem) =>
      switch (problem) {
        BackupProblem.couldNotOpen => l10n.backupCouldNotOpen,
        BackupProblem.notABackup => l10n.backupNotABackup,
        BackupProblem.newerFormat => l10n.backupNewerVersion,
        BackupProblem.damaged => l10n.backupDamaged,
      };

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Re-reads everything a restore can have changed.
  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(settingsProvider)
      ..invalidate(periodStartsProvider)
      ..invalidate(dayEntryProvider)
      ..invalidate(loggedDaysProvider);
  }

  Future<void> _deleteEverything(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(databaseProvider).logDao.deleteEverything();

    // Everything, including the settings rows -- so the app comes back as a
    // fresh install, which is what the confirmation promised and what someone
    // deleting under pressure needs it to mean.
    _refresh(ref);

    if (!context.mounted) return;
    _say(context, l10n.everythingDeleted);
  }
}
