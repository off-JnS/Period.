import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/cycle_mode.dart';
import '../../domain/models/reminder_schedule.dart';
import '../../domain/models/reminder_time.dart';
import '../../l10n/app_localizations.dart';
import '../calendar/calendar_screen.dart' show firstWeekdayOf;

/// What the settings screen shows.
class SettingsViewData {
  /// Creates the view data.
  const SettingsViewData({
    this.cycle = const CycleSettings(),
    this.fertileWindowOptedIn = false,
    this.appLockEnabled = false,
    this.reminder = const ReminderSchedule(),
  });

  /// The mode and its opt-in.
  final CycleSettings cycle;

  /// Whether the fertile window estimate is shown on the Today screen.
  final bool fertileWindowOptedIn;

  /// Whether the app asks the device to confirm it is her before opening.
  final bool appLockEnabled;

  /// When she asked to be reminded to log.
  final ReminderSchedule reminder;
}

/// Where the user says what kind of cycle she has, and erases everything.
///
/// The mode picker is the reason this screen exists. Section 10 requires
/// "predictions are off" to be a first-class state, and until there was a
/// screen to choose it, every user on contraception, pregnant or perimenopausal
/// was given confident estimates that docs/cycle-logic.md section 6 says must
/// never be shown.
///
/// A pure function of [data], like the other screens, so every combination is
/// reachable in a golden without a database.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({
    required this.data,
    this.onModeChanged,
    this.onPredictionsOptInChanged,
    this.onFertileWindowChanged,
    this.onDeleteEverything,
    this.onExportBackup,
    this.onRestoreBackup,
    this.onAppLockChanged,
    this.onReminderChanged,
    this.lockAvailable = true,
    this.remindersAllowed = true,
    super.key,
  });

  /// The current settings.
  final SettingsViewData data;

  /// Whether this device can authenticate at all.
  ///
  /// False when there is no biometric enrolled and no passcode set. The switch
  /// says so rather than silently refusing to move.
  final bool lockAvailable;

  /// Whether the operating system will currently show a notification.
  ///
  /// Only consulted while [SettingsViewData.reminder] is enabled. On a fresh
  /// install this is false because she has never been asked, which is a
  /// different thing from blocked and must not be reported as one.
  final bool remindersAllowed;

  /// Called with the mode the user chose.
  final void Function(CycleMode mode)? onModeChanged;

  /// Called when she asks for estimates despite a mode that disables them.
  final void Function({required bool optedIn})? onPredictionsOptInChanged;

  /// Called when she turns the fertile window estimate on or off.
  final void Function({required bool optedIn})? onFertileWindowChanged;

  /// Called once she has confirmed erasing everything.
  final VoidCallback? onDeleteEverything;

  /// Called to make a backup file.
  final VoidCallback? onExportBackup;

  /// Called to restore from a backup file.
  final VoidCallback? onRestoreBackup;

  /// Called when she turns the app lock on or off.
  final void Function({required bool enabled})? onAppLockChanged;

  /// Called with the whole reminder schedule whenever any part of it changes.
  ///
  /// Whole rather than one field at a time, because the three settings are
  /// written in one transaction: a caller that sent them separately could leave
  /// the time from one choice beside the weekdays from another.
  final void Function(ReminderSchedule schedule)? onReminderChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionHeading(l10n.cycleModeHeading),
            _SectionNote(l10n.cycleModeExplanation),
            RadioGroup<CycleMode>(
              groupValue: data.cycle.mode,
              onChanged: (mode) {
                if (mode != null) onModeChanged?.call(mode);
              },
              child: Column(
                children: [
                  for (final mode in CycleMode.values)
                    RadioListTile<CycleMode>(
                      value: mode,
                      title: Text(_modeLabel(l10n, mode)),
                      subtitle: Text(_modeDetail(l10n, mode)),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),

            // Only under perimenopause. The other two modes have no natural
            // cycle to estimate from, so offering the switch there would imply
            // an estimate exists to be turned on.
            if (data.cycle.mode == CycleMode.perimenopause)
              Padding(
                // Indented to sit under the mode it belongs to. Flush left it
                // reads as a setting of its own, which would be wrong: it only
                // exists while perimenopause is chosen.
                padding: const EdgeInsets.only(left: 32),
                child: SwitchListTile(
                  value: data.cycle.predictionsOptedIn,
                  onChanged: onPredictionsOptInChanged == null
                      ? null
                      : (value) =>
                            onPredictionsOptInChanged!.call(optedIn: value),
                  title: Text(l10n.showEstimatesAnyway),
                  subtitle: Text(l10n.showEstimatesAnywayDetail),
                  isThreeLine: true,
                ),
              ),

            const Divider(height: 24),

            _SectionHeading(l10n.fertileWindowHeading),
            SwitchListTile(
              value: data.fertileWindowOptedIn,
              // Off limits in a mode with no estimate to build one from. The
              // window is counted back from the predicted period, so with
              // predictions disabled turning this on changes nothing at all --
              // and the opt-in two blocks above is hidden for exactly that
              // reason. A switch that silently does nothing is worse than one
              // that says why it cannot.
              onChanged:
                  onFertileWindowChanged == null ||
                      !data.cycle.predictionsEnabled
                  ? null
                  : (value) => onFertileWindowChanged!.call(optedIn: value),
              title: Text(l10n.showFertileWindow),
              // The caveat sits beside the switch, before the choice is made,
              // rather than only on the Today screen after it. Section 8 wants
              // it visible; the moment it matters most is here.
              subtitle: Text(
                data.cycle.predictionsEnabled
                    ? l10n.fertileWindowCaveat
                    : l10n.fertileWindowNeedsEstimates,
              ),
              isThreeLine: true,
            ),

            const Divider(height: 24),

            _SectionHeading(l10n.appLockHeading),
            SwitchListTile(
              value: data.appLockEnabled,
              onChanged: onAppLockChanged == null || !lockAvailable
                  ? null
                  : (value) => onAppLockChanged!.call(enabled: value),
              title: Text(l10n.appLockSwitch),
              // Says two things she needs before choosing: the app keeps no PIN
              // of its own, and it will not trap her out of her own data if the
              // phone cannot authenticate.
              subtitle: Text(
                lockAvailable ? l10n.appLockDetail : l10n.appLockUnavailable,
              ),
              isThreeLine: true,
            ),

            const Divider(height: 24),

            _SectionHeading(l10n.reminderHeading),
            _SectionNote(l10n.reminderExplanation),
            SwitchListTile(
              value: data.reminder.enabled,
              onChanged: onReminderChanged == null
                  ? null
                  : (value) => onReminderChanged!.call(
                      data.reminder.copyWith(enabled: value),
                    ),
              title: Text(l10n.reminderSwitch),
              subtitle: Text(l10n.reminderDetail),
            ),

            // The time and the days appear only once the reminder is on.
            // Shown while it is off they would read as settings that do
            // something, and there is nothing for them to change.
            if (data.reminder.enabled) ...[
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(l10n.reminderTimeLabel),
                trailing: Text(
                  // Formatted by the locale and the device, not by toHhMm():
                  // that is the storage format. Section 3 keeps the wall clock
                  // out of the domain, so turning it into something readable
                  // happens here -- see _formatTime for what that involves.
                  _formatTime(context, data.reminder.time),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: onReminderChanged == null
                    ? null
                    : () => _pickTime(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  l10n.reminderDaysLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              _WeekdayChooser(
                selected: data.reminder.validWeekdays,
                onChanged: onReminderChanged == null
                    ? null
                    : (weekdays) => onReminderChanged!.call(
                        data.reminder.copyWith(weekdays: weekdays),
                      ),
              ),
              // The system is blocking it. Said here rather than left to be
              // discovered by a reminder that never comes -- and said only in
              // this combination, because "not granted" on a fresh install
              // means she has not been asked yet, not that anything is wrong.
              if (!remindersAllowed)
                _ReminderWarning(l10n.reminderBlockedBySystem),

              // On, and nothing will ever fire. Distinct from off, and the one
              // state where saying nothing would look like a bug rather than a
              // choice she made.
              if (data.reminder.validWeekdays.isEmpty)
                _ReminderWarning(l10n.reminderNoDaysChosen),
              const SizedBox(height: 8),
            ],

            const Divider(height: 24),

            _SectionHeading(l10n.backupHeading),
            _SectionNote(l10n.backupExplanation),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text(l10n.exportBackup),
              onTap: onExportBackup,
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l10n.restoreBackup),
              onTap: onRestoreBackup,
            ),

            const Divider(height: 24),

            _SectionHeading(l10n.yourDataHeading),
            _SectionNote(l10n.dataStaysHere),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.deleteAllData,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: onDeleteEverything == null
                  ? null
                  : () => _confirmDelete(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Asks before erasing, and never erases from the tap alone.
  ///
  /// A dialogue rather than the undo used elsewhere for saving: undo needs
  /// something to restore, and after this there is nothing anywhere to restore
  /// from. Section 9 requires the deletion to be real, which is exactly why it
  /// has to be deliberate.
  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAllDataConfirmTitle),
        content: Text(l10n.deleteAllDataConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(l10n.deleteEverything),
          ),
        ],
      ),
    );

    if (confirmed ?? false) onDeleteEverything?.call();
  }

  /// The chosen time, as this locale and this phone write a time of day.
  ///
  /// Through [MaterialLocalizations] rather than [ReminderTime.toHhMm], which
  /// is the storage format: a locale on a 12-hour clock should see "8:00 PM".
  ///
  /// `alwaysUse24HourFormat` looks optional and is not. It defaults to false,
  /// while [showTimePicker] reads the device's own 24-hour setting -- so left
  /// at the default, an English user whose phone is set to 24-hour time would
  /// pick 20:00 in the dial and read "8:00 PM" back on this row. German hid
  /// that for a while, because its locale writes a 24-hour clock either way.
  String _formatTime(BuildContext context, ReminderTime time) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: time.hour, minute: time.minute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  /// Opens the system time picker and reports what she chose.
  ///
  /// [TimeOfDay] appears here and goes no further. It is a Flutter type, so
  /// section 2 keeps it out of the domain entirely -- which is why
  /// [ReminderTime] exists -- and this is the boundary where one becomes the
  /// other.
  Future<void> _pickTime(BuildContext context) async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: data.reminder.time.hour,
        minute: data.reminder.time.minute,
      ),
    );
    if (chosen == null) return;

    onReminderChanged?.call(
      data.reminder.copyWith(
        time: ReminderTime.checked(chosen.hour, chosen.minute),
      ),
    );
  }
}

/// The days of the week, as chips she can switch on and off.
///
/// Chips rather than seven switches: the whole week has to be readable at a
/// glance, and a column of seven rows is not.
class _WeekdayChooser extends StatelessWidget {
  const _WeekdayChooser({required this.selected, this.onChanged});

  /// The chosen weekdays, 1 (Monday) through 7 (Sunday).
  final Set<int> selected;

  final void Function(Set<int> weekdays)? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    // Same two formats and the same trick as the calendar's own weekday
    // headings: January 2024 began on a Monday, so the day of the month and
    // the ISO weekday number line up.
    final short = DateFormat.E(locale);
    final full = DateFormat.EEEE(locale);
    // The reader's own week. Germany starts on Monday and the United States on
    // Sunday, and a chooser that disagreed with the calendar two screens away
    // would be its own small bug.
    final first = firstWeekdayOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final weekday = (first - 1 + i) % 7 + 1;
                final date = DateTime(2024, 1, weekday);
                final isSelected = selected.contains(weekday);

                return Semantics(
                  // The chip shows one letter or two, which several weekdays
                  // share and which reads as nothing aloud. Selection is spoken
                  // as well, so it is never carried by colour -- or by a
                  // checkmark nobody can see -- alone.
                  label: isSelected
                      ? l10n.reminderDaySelected(full.format(date))
                      : l10n.reminderDayNotSelected(full.format(date)),
                  excludeSemantics: true,
                  // Both, and `selected` is the one that matters. Excluding the
                  // chip's own semantics to replace its short label also throws
                  // away the `selected` flag it sets, leaving a plain button
                  // whose state lives only in the words above -- so a screen
                  // reader would not announce the state *changing* on a tap,
                  // and nothing but prose would say it is selectable at all.
                  selected: isSelected,
                  button: true,
                  child: FilterChip(
                    label: Text(short.format(date)),
                    selected: isSelected,
                    onSelected: onChanged == null
                        ? null
                        : (value) => onChanged!.call(
                            {...selected, if (value) weekday}
                              ..removeWhere((day) => !value && day == weekday),
                          ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// A reason no reminder will arrive.
///
/// Both cases it serves look identical to the user -- the switch is on and
/// nothing comes -- so they are said the same way, and neither is left to be
/// inferred from silence.
///
/// An icon as well as the colour. Section 9: no state is ever carried by colour
/// alone, which matters most here, where the whole content is a warning.
class _ReminderWarning extends StatelessWidget {
  const _ReminderWarning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _modeLabel(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.natural => l10n.modeNatural,
  CycleMode.hormonalContraception => l10n.modeContraception,
  CycleMode.pregnancy => l10n.modePregnancy,
  CycleMode.perimenopause => l10n.modePerimenopause,
};

/// What each mode does, in place beside the choice.
///
/// Section 10 requires every mode to say *why* estimates are off. Saying it
/// only on the Today screen would leave the user choosing blind here.
String _modeDetail(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.natural => l10n.modeNaturalDetail,
  CycleMode.hormonalContraception => l10n.modeContraceptionDetail,
  CycleMode.pregnancy => l10n.modePregnancyDetail,
  CycleMode.perimenopause => l10n.modePerimenopauseDetail,
};
