import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/cycle_date.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'today/log_entry_sheet.dart';

/// Records or corrects what happened on [date].
///
/// Shared by every screen that can log, rather than reimplemented per screen.
/// The undo path below is the only route back from a mistap that would otherwise
/// silently change every estimate in the app, and a second copy of it would
/// eventually drift out of step with this one.
Future<void> logDay(BuildContext context, WidgetRef ref, CycleDate date) async {
  final l10n = AppLocalizations.of(context);
  final database = ref.read(databaseProvider);
  final existing = await database.logDao.entryOn(date);
  final starts = await database.logDao.allPeriodStarts();

  if (!context.mounted) return;

  final result = await showModalBottomSheet<LoggedDay>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => LogEntrySheet(
      date: date,
      existing: existing,
      isPeriodStart: starts.contains(date),
    ),
  );
  if (result == null) return;

  await database.logDao.saveEntry(result.entry);
  // Marking is separate from the entry: section 4 makes period starts the
  // source of truth for cycle boundaries, so this is what actually moves the
  // prediction. Unmarking has to work too -- a mis-tap should be correctable.
  final wasPeriodStart = starts.contains(date);
  if (result.isPeriodStart) {
    await database.logDao.addPeriodStart(date);
  } else {
    await database.logDao.removePeriodStart(date);
  }

  // Removing a period start is destructive in a way saving a note is not: it
  // silently changes every estimate on the screen. Offering undo is cheaper
  // and less obstructive than a confirmation dialogue, and it is the only
  // route back from a mistap.
  final undoable = wasPeriodStart && !result.isPeriodStart;

  _refresh(ref);

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
                  await database.logDao.addPeriodStart(date);
                  _refresh(ref);
                },
              )
            : null,
      ),
    );
}

/// Re-reads everything a save can have changed.
///
/// Everything on every screen is derived on read from these rows (section 4),
/// so invalidating the reads refreshes the cycle day, the estimate, the fertile
/// window, the hint and the calendar together, with no cache to keep in step.
/// The families are invalidated whole: a save to one day changes the month grid
/// that contains it, and which range is on screen is not knowable from here.
void _refresh(WidgetRef ref) {
  ref
    ..invalidate(periodStartsProvider)
    ..invalidate(dayEntryProvider)
    ..invalidate(loggedDaysProvider);
}
