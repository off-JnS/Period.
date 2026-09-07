import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import 'log_entry_sheet.dart';
import 'today_screen.dart';

/// The Today screen connected to the database.
///
/// Kept separate from [TodayScreen], which stays a pure function of its input so
/// that every state can be rendered in a golden file without a database. This
/// is the thin layer that reads real data and writes it back.
class TodayPage extends ConsumerWidget {
  /// Creates the page.
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(todayViewDataProvider);

    return data.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.todayTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      // Never the raw exception. A user who cannot open her cycle data needs to
      // know what happened and what to do, not a stack trace -- and section 8
      // puts every user-facing string in the ARB files, which a formatted error
      // object can never be.
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: Text(l10n.todayTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.couldNotOpenData,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.couldNotOpenDataDetail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref.invalidate(periodStartsProvider),
                  child: Text(l10n.tryAgain),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (view) =>
          TodayScreen(data: view, onLogToday: () => _log(context, ref)),
    );
  }

  Future<void> _log(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final today = ref.read(clockProvider).today();
    final database = ref.read(databaseProvider);
    final existing = await database.logDao.entryOn(today);
    final starts = await database.logDao.allPeriodStarts();

    if (!context.mounted) return;

    final result = await showModalBottomSheet<LoggedDay>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => LogEntrySheet(
        date: today,
        existing: existing,
        isPeriodStart: starts.contains(today),
      ),
    );
    if (result == null) return;

    await database.logDao.saveEntry(result.entry);
    // Marking is separate from the entry: section 4 makes period starts the
    // source of truth for cycle boundaries, so this is what actually moves the
    // prediction. Unmarking has to work too -- a mis-tap should be correctable.
    final wasPeriodStart = starts.contains(today);
    if (result.isPeriodStart) {
      await database.logDao.addPeriodStart(today);
    } else {
      await database.logDao.removePeriodStart(today);
    }

    // Removing a period start is destructive in a way saving a note is not: it
    // silently changes every estimate on the screen. Offering undo is cheaper
    // and less obstructive than a confirmation dialogue, and it is the only
    // route back from a mistap.
    final undoable = wasPeriodStart && !result.isPeriodStart;

    // Re-read. Everything on the screen is derived on read from these dates
    // (section 4), so this one invalidation refreshes the cycle day, the
    // estimate, the fertile window and the hint together, with no cache to keep
    // in step.
    ref.invalidate(periodStartsProvider);

    if (!context.mounted) return;
    // Replace rather than queue. A confirmation from a previous save is stale
    // the moment another one happens, and queueing would leave the newer
    // message -- including its undo -- waiting behind a message about an edit
    // the user has already moved on from.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.entrySaved),
          action: undoable
              ? SnackBarAction(
                  label: l10n.undo,
                  onPressed: () async {
                    await database.logDao.addPeriodStart(today);
                    ref.invalidate(periodStartsProvider);
                  },
                )
              : null,
        ),
      );
  }
}
