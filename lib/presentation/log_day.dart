import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/logic/reminder_schedule.dart';
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

  await _dropTodaysReminder(l10n, ref, date);

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

/// Drops a reminder that [date] has just made unnecessary.
///
/// docs/cycle-logic.md section 7: a reminder to do a thing already done is
/// noise, and an app that generates noise gets its notifications switched off
/// entirely, taking the useful ones with it.
///
/// Only for today. A correction to last Tuesday says nothing about whether
/// tonight's reminder is still wanted, and cancelling on one would silently
/// drop a reminder she never asked to lose.
///
/// [shouldRemindOn] is asked rather than reimplemented, so the rule has one
/// definition and it is the tested one.
///
/// Takes the localisations rather than a [BuildContext]: the strings are needed
/// after two awaits, and a context is not safe to read across those.
Future<void> _dropTodaysReminder(
  AppLocalizations l10n,
  WidgetRef ref,
  CycleDate date,
) async {
  final clock = ref.read(clockProvider);
  if (date != clock.today()) return;

  final schedule =
      (await ref.read(databaseProvider).settingsDao.readSettings()).reminder;

  // Asked with nothing logged, which is the only question worth asking here:
  // *was* a reminder wanted on this day? Passing the day as logged instead
  // always answers false -- for a day already logged, but equally for reminders
  // being off and for a weekday she never chose -- so it would drop a reminder
  // in two cases where there is nothing to drop.
  if (!shouldRemindOn(schedule: schedule, date: date, loggedDays: const {})) {
    return;
  }

  await ref
      .read(remindersProvider)
      .skipToday(
        schedule,
        today: date,
        title: l10n.reminderNotificationTitle,
        body: l10n.reminderNotificationBody,
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
