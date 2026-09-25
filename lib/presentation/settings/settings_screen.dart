import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/app_preferences.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/reminder_settings.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../theme.dart';

/// The user's choices, laid out like iOS Settings.
///
/// Presentation only: it renders [settings] and reports every change through
/// [onChanged]. It never saves anything itself, so each state is reachable in a
/// widget test without a database.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({
    required this.settings,
    required this.onChanged,
    this.preferences = const AppPreferences(),
    this.onPreferencesChanged,
    this.lockEnabled,
    this.onLockChanged,
    this.lockUnavailable = false,
    this.reminders,
    this.onRemindersChanged,
    this.remindersBlocked = false,
    this.onEraseEverything,
    super.key,
  });

  /// Starts deleting all data. Null hides the row.
  final VoidCallback? onEraseEverything;

  /// The reminder settings, or null to leave the reminders group out.
  final ReminderSettings? reminders;

  /// Called with the whole new reminder settings on any change.
  final ValueChanged<ReminderSettings>? onRemindersChanged;

  /// Whether notifications were refused, so reminders cannot arrive.
  final bool remindersBlocked;

  /// Whether the app lock is on, or null to leave the privacy group out.
  final bool? lockEnabled;

  /// Called when she flips the lock switch. Null disables the switch.
  final ValueChanged<bool>? onLockChanged;

  /// Whether the last attempt to turn the lock on found no device passcode.
  final bool lockUnavailable;

  /// The current appearance and language.
  final AppPreferences preferences;

  /// Called with the whole new preferences whenever the user changes one.
  /// Null leaves the choices visible but inert, as in a test of the cycle
  /// settings alone.
  final ValueChanged<AppPreferences>? onPreferencesChanged;

  /// What is currently chosen.
  final CycleSettings settings;

  /// Called with the whole new settings whenever the user changes anything.
  final ValueChanged<CycleSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    void change(CycleSettings next) {
      HapticFeedback.selectionClick();
      onChanged(next);
    }

    void changePreferences(AppPreferences next) {
      final report = onPreferencesChanged;
      if (report == null) return;
      HapticFeedback.selectionClick();
      report(next);
    }

    return GroupedPage(
      title: l10n.settingsTitle,
      children: [
        GroupHeader(l10n.cycleModeHeading),
        _CheckList(
          options: CycleMode.values,
          selected: settings.mode,
          label: (mode) => modeLabel(l10n, mode),
          onSelected: (mode) => change(settings.copyWith(mode: mode)),
        ),
        // Every mode explains itself, including why estimates are off where
        // they are: section 10 treats "predictions off" as a state to be
        // stated, not an absence to be noticed.
        GroupFooter(_modeFooter(l10n, settings.mode)),
        if (settings.mode == CycleMode.perimenopause) ...[
          const SizedBox(height: 28),
          _SwitchGroup(
            title: l10n.showEstimatesAnyway,
            value: settings.predictionsOptedIn,
            onChanged: (value) =>
                change(settings.copyWith(predictionsOptedIn: value)),
            footer: l10n.showEstimatesAnywayFooter,
          ),
        ],
        // Offered only where there is a period estimate to count back from.
        // In any other mode the switch would do nothing, and a control that
        // does nothing reads as broken.
        if (settings.predictionsEnabled) ...[
          const SizedBox(height: 28),
          _SwitchGroup(
            title: l10n.fertileWindowHeading,
            value: settings.fertileWindowOptedIn,
            onChanged: (value) =>
                change(settings.copyWith(fertileWindowOptedIn: value)),
            // Section 8: the caveat sits beside the switch, visible before
            // she turns it on, never behind a tap.
            footer: l10n.fertileWindowCaveat,
          ),
        ],
        if (reminders case final current?) ...[
          const SizedBox(height: 28),
          GroupHeader(l10n.remindersHeading),
          _RemindersCard(reminders: current, onChanged: onRemindersChanged),
          GroupFooter(
            remindersBlocked ? l10n.remindersBlocked : l10n.remindersFooter,
          ),
        ],
        if (lockEnabled case final enabled?) ...[
          const SizedBox(height: 28),
          GroupHeader(l10n.privacyHeading),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: enabled,
              onChanged: onLockChanged == null
                  ? null
                  : (value) {
                      HapticFeedback.selectionClick();
                      onLockChanged!(value);
                    },
              title: Text(l10n.appLockToggle),
            ),
          ),
          GroupFooter(
            lockUnavailable ? l10n.appLockUnavailable : l10n.appLockFooter,
          ),
        ],
        const SizedBox(height: 28),
        GroupHeader(l10n.appearanceHeading),
        _CheckList(
          options: AppearanceChoice.values,
          selected: preferences.appearance,
          label: (choice) => switch (choice) {
            AppearanceChoice.system => l10n.appearanceSystem,
            AppearanceChoice.light => l10n.appearanceLight,
            AppearanceChoice.dark => l10n.appearanceDark,
          },
          onSelected: (choice) =>
              changePreferences(preferences.copyWith(appearance: choice)),
        ),
        if (preferences.appearance == AppearanceChoice.system)
          GroupFooter(l10n.appearanceSystemFooter),
        const SizedBox(height: 28),
        GroupHeader(l10n.languageHeading),
        _CheckList(
          options: LanguageChoice.values,
          selected: preferences.language,
          label: (choice) => switch (choice) {
            LanguageChoice.system => l10n.languageSystem,
            LanguageChoice.german => l10n.languageNameGerman,
            LanguageChoice.english => l10n.languageNameEnglish,
          },
          onSelected: (choice) =>
              changePreferences(preferences.copyWith(language: choice)),
        ),
        if (preferences.language == LanguageChoice.system)
          GroupFooter(l10n.languageSystemFooter),
        const SizedBox(height: 28),
        GroupFooter(l10n.settingsStoredEncrypted),
        if (onEraseEverything case final erase?) ...[
          const SizedBox(height: 28),
          // Alone at the very bottom, in red, as iOS places "Erase All
          // Content and Settings": far from anything tapped by habit.
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: erase,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Center(
                    child: Text(
                      l10n.eraseAllData,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          GroupFooter(l10n.eraseAllFooter),
        ],
      ],
    );
  }
}

/// The display name of [mode].
String modeLabel(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.natural => l10n.modeNatural,
  CycleMode.hormonalContraception => l10n.modeHormonalContraception,
  CycleMode.pregnancy => l10n.modePregnancy,
  CycleMode.perimenopause => l10n.modePerimenopause,
};

String _modeFooter(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.natural => l10n.modeNaturalFooter,
  CycleMode.hormonalContraception => l10n.modeContraceptionFooter,
  CycleMode.pregnancy => l10n.modePregnancyFooter,
  CycleMode.perimenopause => l10n.modePerimenopauseFooter,
};

/// A checkmark list, as iOS uses for picking one option from a few.
///
/// Rows wrap rather than truncate, so it holds up at large text sizes and in
/// German where a segmented control would not.
class _CheckList<T> extends StatelessWidget {
  const _CheckList({
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T option) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const Divider(indent: 16),
            Semantics(
              selected: option == selected,
              inMutuallyExclusiveGroup: true,
              button: true,
              excludeSemantics: true,
              label: label(option),
              child: InkWell(
                onTap: option == selected ? null : () => onSelected(option),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label(option),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        // The checkmark is a shape as well as a colour, so the
                        // selection never rests on colour alone.
                        if (option == selected)
                          Icon(
                            Icons.check_rounded,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchGroup extends StatelessWidget {
  const _SwitchGroup({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.footer,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: value,
            onChanged: onChanged,
            title: Text(title),
          ),
        ),
        GroupFooter(footer),
      ],
    );
  }
}

/// The reminder switches, and the lead time and time of day once one is on.
class _RemindersCard extends StatelessWidget {
  const _RemindersCard({required this.reminders, required this.onChanged});

  final ReminderSettings reminders;
  final ValueChanged<ReminderSettings>? onChanged;

  void _change(ReminderSettings next) {
    final report = onChanged;
    if (report == null) return;
    HapticFeedback.selectionClick();
    report(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onChanged != null;

    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: reminders.hour, minute: reminders.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: reminders.periodComing,
            onChanged: enabled
                ? (value) => _change(reminders.copyWith(periodComing: value))
                : null,
            title: Text(l10n.reminderPeriodComing),
          ),
          if (reminders.periodComing) ...[
            const Divider(indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.reminderDaysBefore,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  // Five plain numbers: short enough for a segmented control
                  // at any text size, where a wheel would be overkill.
                  CupertinoSlidingSegmentedControl<int>(
                    groupValue: reminders.daysBefore,
                    thumbColor: scheme.groupedCard,
                    backgroundColor: scheme.groupedBackground,
                    onValueChanged: (days) {
                      if (days != null && enabled) {
                        _change(reminders.copyWith(daysBefore: days));
                      }
                    },
                    children: {
                      for (
                        var days = ReminderSettings.minDaysBefore;
                        days <= ReminderSettings.maxDaysBefore;
                        days++
                      )
                        days: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '$days',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                    },
                  ),
                ],
              ),
            ),
          ],
          const Divider(indent: 16),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: reminders.dailyLog,
            onChanged: enabled
                ? (value) => _change(reminders.copyWith(dailyLog: value))
                : null,
            title: Text(l10n.reminderDailyLog),
          ),
          if (reminders.anyEnabled) ...[
            const Divider(indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.reminderTime,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '${l10n.reminderTime}: $time',
                    excludeSemantics: true,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(44, 44),
                      color: scheme.groupedBackground,
                      borderRadius: BorderRadius.circular(8),
                      onPressed: enabled ? () => _pickTime(context) : null,
                      child: Text(
                        time,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    var hour = reminders.hour;
    var minute = reminders.minute;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 280,
        color: Theme.of(context).colorScheme.groupedCard,
        child: SafeArea(
          top: false,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
            minuteInterval: 5,
            // A DateTime only as the wheel's starting position; the day part
            // is meaningless and nothing here is stored as a timestamp.
            initialDateTime: DateTime(2000, 1, 1, hour, minute - minute % 5),
            onDateTimeChanged: (picked) {
              hour = picked.hour;
              minute = picked.minute;
            },
          ),
        ),
      ),
    );
    if (hour != reminders.hour || minute != reminders.minute) {
      _change(reminders.copyWith(hour: hour, minute: minute));
    }
  }
}
