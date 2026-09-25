import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/app_preferences.dart';
import '../../domain/models/reminder_settings.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_controls.dart';
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
    this.preferences = const AppPreferences(),
    this.onPreferencesChanged,
    this.lockEnabled,
    this.onLockChanged,
    this.lockUnavailable = false,
    this.reminders,
    this.onRemindersChanged,
    this.remindersBlocked = false,
    this.onEraseEverything,
    this.widgetDetailed,
    this.onWidgetDetailedChanged,
    this.backLabel,
    super.key,
  });

  /// Whether the home-screen widget shows details, or null to leave the
  /// widget group out.
  final bool? widgetDetailed;

  /// Called when she flips the widget switch.
  final ValueChanged<bool>? onWidgetDetailedChanged;

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
  /// Null leaves the choices visible but inert.
  final ValueChanged<AppPreferences>? onPreferencesChanged;

  /// The profile's title, for the back button, when Settings was opened
  /// from it.
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    void changePreferences(AppPreferences next) {
      final report = onPreferencesChanged;
      if (report == null) return;
      HapticFeedback.selectionClick();
      report(next);
    }

    return GroupedPage(
      title: l10n.settingsTitle,
      backLabel: backLabel,
      children: [
        if (reminders case final current?) ...[
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
        if (widgetDetailed case final detailed?) ...[
          const SizedBox(height: 28),
          GroupHeader(l10n.widgetHeading),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: detailed,
              onChanged: onWidgetDetailedChanged == null
                  ? null
                  : (value) {
                      HapticFeedback.selectionClick();
                      onWidgetDetailedChanged!(value);
                    },
              title: Text(l10n.widgetDetailedToggle),
            ),
          ),
          GroupFooter(
            detailed ? l10n.widgetDetailedFooter : l10n.widgetDiscreetFooter,
          ),
        ],
        const SizedBox(height: 28),
        GroupHeader(l10n.appearanceHeading),
        CheckList(
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
        CheckList(
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
