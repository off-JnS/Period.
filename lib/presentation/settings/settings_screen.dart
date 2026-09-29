import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/models/app_preferences.dart';
import '../../domain/models/reminder_settings.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_controls.dart';
import '../grouped_page.dart';

/// Keys for Settings' rows, so tests can reach them without text.
abstract final class SettingsKeys {
  /// The row that opens the reminders page.
  static const reminders = ValueKey('settings.reminders');
}

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
    this.onOpenReminders,
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

  /// Opens the reminders page.
  final VoidCallback? onOpenReminders;

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
      report(next);
    }

    return GroupedPage(
      title: l10n.settingsTitle,
      backLabel: backLabel,
      children: [
        if (reminders case final current?) ...[
          GroupHeader(l10n.remindersHeading),
          // Its own page: the cycle's reminders and the one for her
          // contraception have more to set than fits in a group here.
          Card(
            clipBehavior: Clip.antiAlias,
            child: ValueRow(
              key: SettingsKeys.reminders,
              icon: current.anyEnabled
                  ? CupertinoIcons.bell_fill
                  : CupertinoIcons.bell,
              label: l10n.remindersHeading,
              value: current.anyEnabled ? l10n.remindersOn : l10n.remindersOff,
              onTap: onOpenReminders ?? () {},
            ),
          ),
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
