import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/logic/profile.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_controls.dart';
import '../grouped_page.dart';
import '../theme.dart';
import 'cycle_mode_section.dart';
import 'profile_labels.dart';

/// Keys for the profile rows, so tests can reach them without matching text.
abstract final class ProfileKeys {
  /// The birth year row.
  static const birthYear = ValueKey('profile.birthYear');

  /// The usual cycle length row.
  static const cycleLength = ValueKey('profile.cycleLength');

  /// The usual period length row.
  static const periodLength = ValueKey('profile.periodLength');

  /// The contraception row.
  static const contraception = ValueKey('profile.contraception');

  /// The conditions row.
  static const conditions = ValueKey('profile.conditions');

  /// The picker wheel in the number popups.
  static const wheel = ValueKey('profile.wheel');
}

/// What she has told the app about herself, and her cycle mode.
///
/// Presentation only: it renders [profile] and [settings] and reports every
/// change. It never saves anything itself.
class ProfileScreen extends StatelessWidget {
  /// Creates the screen.
  const ProfileScreen({
    required this.profile,
    required this.settings,
    required this.currentYear,
    required this.onProfileChanged,
    required this.onSettingsChanged,
    this.onOpenSettings,
    super.key,
  });

  /// What she has said about herself.
  final Profile profile;

  /// Her cycle mode and its switches.
  final CycleSettings settings;

  /// This calendar year, for her age and the birth years on offer.
  final int currentYear;

  /// Called with the whole new profile on any change.
  final ValueChanged<Profile> onProfileChanged;

  /// Called with the whole new cycle settings on any change.
  final ValueChanged<CycleSettings> onSettingsChanged;

  /// Opens Settings. Null hides the gear.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = offersContraceptionMode(profile, settings);

    return GroupedPage(
      title: l10n.profileTitle,
      trailing: onOpenSettings == null
          ? null
          : Semantics(
              button: true,
              label: l10n.settingsTitle,
              excludeSemantics: true,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: onOpenSettings,
                child: const Icon(CupertinoIcons.gear_alt, size: 24),
              ),
            ),
      children: [
        _Header(profile: profile, settings: settings, currentYear: currentYear),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: offer
              ? Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ContraceptionOffer(
                    onAccept: () {
                      onSettingsChanged(
                        settings.copyWith(
                          mode: CycleMode.hormonalContraception,
                        ),
                      );
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 28),
        GroupHeader(l10n.aboutMeHeading),
        AboutMeCard(
          profile: profile,
          currentYear: currentYear,
          onChanged: onProfileChanged,
          backLabel: l10n.profileTitle,
        ),
        GroupFooter(l10n.aboutMeFooter),
        const SizedBox(height: 28),
        CycleModeSection(settings: settings, onChanged: onSettingsChanged),
      ],
    );
  }
}

/// The rows she answers about herself: birth year, usual lengths,
/// contraception and diagnosed conditions. Shared by Profile and onboarding.
class AboutMeCard extends StatelessWidget {
  /// Creates the card.
  const AboutMeCard({
    required this.profile,
    required this.currentYear,
    required this.onChanged,
    required this.backLabel,
    super.key,
  });

  /// What she has said so far.
  final Profile profile;

  /// This calendar year, for the birth years on offer.
  final int currentYear;

  /// Called with the whole new profile on any change.
  final ValueChanged<Profile> onChanged;

  /// The title the pushed pickers name on their back button.
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ValueRow(
            key: ProfileKeys.birthYear,
            icon: CupertinoIcons.gift,
            label: l10n.birthYearLabel,
            value: profile.birthYear?.toString() ?? l10n.notSet,
            placeholder: profile.birthYear == null,
            onTap: () => _pickNumber(
              context,
              title: l10n.birthYearLabel,
              values: birthYearChoices(currentYear),
              current: profile.birthYear,
              initial: currentYear - 25,
              format: (year) => '$year',
              onPicked: (year) => onChanged(profile.copyWith(birthYear: year)),
            ),
          ),
          const Divider(indent: 56),
          ValueRow(
            key: ProfileKeys.cycleLength,
            icon: CupertinoIcons.arrow_2_circlepath,
            label: l10n.usualCycleLabel,
            value: _days(l10n, profile.usualCycleLength),
            placeholder: profile.usualCycleLength == null,
            onTap: () => _pickNumber(
              context,
              title: l10n.usualCycleLabel,
              values: [
                for (
                  var days = Profile.minCycleLength;
                  days <= Profile.maxCycleLength;
                  days++
                )
                  days,
              ],
              current: profile.usualCycleLength,
              initial: 28,
              format: l10n.lengthInDays,
              onPicked: (days) =>
                  onChanged(profile.copyWith(usualCycleLength: days)),
            ),
          ),
          const Divider(indent: 56),
          ValueRow(
            key: ProfileKeys.periodLength,
            icon: CupertinoIcons.drop,
            label: l10n.usualPeriodLabel,
            value: _days(l10n, profile.usualPeriodLength),
            placeholder: profile.usualPeriodLength == null,
            onTap: () => _pickNumber(
              context,
              title: l10n.usualPeriodLabel,
              values: [
                for (
                  var days = Profile.minPeriodLength;
                  days <= Profile.maxPeriodLength;
                  days++
                )
                  days,
              ],
              current: profile.usualPeriodLength,
              initial: 5,
              format: l10n.lengthInDays,
              onPicked: (days) =>
                  onChanged(profile.copyWith(usualPeriodLength: days)),
            ),
          ),
          const Divider(indent: 56),
          ValueRow(
            key: ProfileKeys.contraception,
            icon: CupertinoIcons.shield,
            label: l10n.contraceptionLabel,
            value: switch (profile.contraception) {
              final method? => methodLabel(l10n, method),
              null => l10n.notSet,
            },
            placeholder: profile.contraception == null,
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => _ContraceptionPicker(
                  backLabel: backLabel,
                  current: profile.contraception,
                  onPicked: (method) =>
                      onChanged(profile.copyWith(contraception: method)),
                ),
              ),
            ),
          ),
          const Divider(indent: 56),
          ValueRow(
            key: ProfileKeys.conditions,
            icon: CupertinoIcons.heart_circle,
            label: l10n.conditionsLabel,
            value: conditionsSummary(l10n, profile.conditions),
            placeholder: profile.conditions.isEmpty,
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => _ConditionsPicker(
                  backLabel: backLabel,
                  initial: profile.conditions,
                  onChanged: (conditions) =>
                      onChanged(profile.copyWith(conditions: conditions)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _days(AppLocalizations l10n, int? days) =>
      days == null ? l10n.notSet : l10n.lengthInDays(days);
}

/// The avatar, her age and her mode, at the top as in the Health profile.
class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.settings,
    required this.currentYear,
  });

  final Profile profile;
  final CycleSettings settings;
  final int currentYear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final age = ageThisYear(
      birthYear: profile.birthYear,
      currentYear: currentYear,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    scheme.primary.withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: Icon(
                CupertinoIcons.person_fill,
                size: 44,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              age == null
                  ? l10n.profileEmptyPrompt
                  : l10n.profileAgeThisYear(age),
              key: ValueKey(age),
              textAlign: TextAlign.center,
              style: age == null
                  ? theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )
                  : theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  modeIcon(settings.mode),
                  size: 16,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  modeLabel(l10n, settings.mode),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The offer to switch to the contraception mode. docs/cycle-logic.md §10:
/// offered, never done for her.
class ContraceptionOffer extends StatelessWidget {
  /// Creates the offer.
  const ContraceptionOffer({required this.onAccept, super.key});

  /// Switches to the contraception mode.
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RowIcon(CupertinoIcons.capsule),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.contraceptionOffer,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: CupertinoButton(
                minimumSize: const Size(44, 44),
                onPressed: onAccept,
                child: Text(
                  l10n.contraceptionOfferAccept,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wheel popup for a number, with Clear and Done, as iOS pickers have.
///
/// Nothing is saved while the wheel turns: only Done keeps the value, and
/// tapping outside leaves everything as it was.
Future<void> _pickNumber(
  BuildContext context, {
  required String title,
  required List<int> values,
  required int? current,
  required int initial,
  required String Function(int value) format,
  required ValueChanged<int?> onPicked,
}) async {
  final l10n = AppLocalizations.of(context);
  final start = values.indexOf(current ?? initial);
  var index = start < 0 ? 0 : start;
  var result = (picked: false, value: current);

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return Material(
        color: scheme.groupedCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (current != null)
                      CupertinoButton(
                        onPressed: () {
                          result = (picked: true, value: null);
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          l10n.clearAnswer,
                          style: TextStyle(
                            color: CupertinoColors.systemRed.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 72),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () {
                        result = (picked: true, value: values[index]);
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        l10n.doneButton,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 216,
                child: CupertinoPicker(
                  key: ProfileKeys.wheel,
                  itemExtent: 36,
                  scrollController: FixedExtentScrollController(
                    initialItem: index,
                  ),
                  onSelectedItemChanged: (value) {
                    index = value;
                  },
                  children: [
                    for (final value in values)
                      Center(
                        child: Text(
                          format(value),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (result.picked && result.value != current) onPicked(result.value);
}

/// The contraception list, pushed like a Settings sub-page.
class _ContraceptionPicker extends StatelessWidget {
  const _ContraceptionPicker({
    required this.current,
    required this.onPicked,
    required this.backLabel,
  });

  final ContraceptionMethod? current;
  final String backLabel;
  final ValueChanged<ContraceptionMethod?> onPicked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    void pick(ContraceptionMethod? method) {
      onPicked(method);
      Navigator.of(context).pop();
    }

    return GroupedPage(
      title: l10n.contraceptionLabel,
      backLabel: backLabel,
      trailing: current == null
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => pick(null),
              child: Text(l10n.clearAnswer),
            ),
      children: [
        // Hormonal methods apart from the rest, since that is the line the
        // app draws (docs/cycle-logic.md §10): only a hormonal method offers
        // the contraception mode.
        CheckList(
          options: const [ContraceptionMethod.none],
          selected: current,
          label: (method) => methodLabel(l10n, method),
          icon: methodIcon,
          onSelected: pick,
        ),
        const SizedBox(height: 24),
        GroupHeader(l10n.methodsHormonal),
        CheckList(
          options: [
            for (final method in ContraceptionMethod.values)
              if (method.hormonal) method,
          ],
          selected: current,
          label: (method) => methodLabel(l10n, method),
          icon: methodIcon,
          onSelected: pick,
        ),
        GroupFooter(l10n.methodsHormonalFooter),
        const SizedBox(height: 28),
        GroupHeader(l10n.methodsNonHormonal),
        CheckList(
          options: [
            for (final method in ContraceptionMethod.values)
              if (!method.hormonal &&
                  method != ContraceptionMethod.none &&
                  method != ContraceptionMethod.other)
                method,
          ],
          selected: current,
          label: (method) => methodLabel(l10n, method),
          icon: methodIcon,
          onSelected: pick,
        ),
        GroupFooter(l10n.methodsNonHormonalFooter),
        const SizedBox(height: 28),
        CheckList(
          options: const [ContraceptionMethod.other],
          selected: current,
          label: (method) => methodLabel(l10n, method),
          icon: methodIcon,
          onSelected: pick,
        ),
      ],
    );
  }
}

/// The diagnosed-conditions list. Any number may be checked; each tap is
/// saved at once, as a Settings list is.
class _ConditionsPicker extends StatefulWidget {
  const _ConditionsPicker({
    required this.initial,
    required this.onChanged,
    required this.backLabel,
  });

  final Set<KnownCondition> initial;
  final String backLabel;
  final ValueChanged<Set<KnownCondition>> onChanged;

  @override
  State<_ConditionsPicker> createState() => _ConditionsPickerState();
}

class _ConditionsPickerState extends State<_ConditionsPicker> {
  late Set<KnownCondition> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GroupedPage(
      title: l10n.conditionsLabel,
      backLabel: widget.backLabel,
      children: [
        MultiCheckList(
          options: KnownCondition.values,
          selected: _selected,
          label: (condition) => conditionLabel(l10n, condition),
          onToggled: (condition) {
            final next = {..._selected};
            if (!next.remove(condition)) next.add(condition);
            setState(() => _selected = next);
            widget.onChanged(next);
          },
        ),
        GroupFooter(l10n.conditionsFooter),
      ],
    );
  }
}
