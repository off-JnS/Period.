import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/app_preferences.dart';
import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';

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
    super.key,
  });

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
