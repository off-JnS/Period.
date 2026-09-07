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
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: Text(l10n.todayTitle)),
        body: Center(child: Text('$error')),
      ),
      data: (view) =>
          TodayScreen(data: view, onLogToday: () => _log(context, ref)),
    );
  }

  Future<void> _log(BuildContext context, WidgetRef ref) async {
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
    if (result.isPeriodStart) {
      await database.logDao.addPeriodStart(today);
    } else {
      await database.logDao.removePeriodStart(today);
    }

    // Re-read. Everything on the screen is derived on read from these dates
    // (section 4), so this one invalidation refreshes the cycle day, the
    // estimate, the fertile window and the hint together, with no cache to keep
    // in step.
    ref.invalidate(periodStartsProvider);
  }
}
