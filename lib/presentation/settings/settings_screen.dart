import 'package:flutter/material.dart';

import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';

/// What the settings screen shows.
class SettingsViewData {
  /// Creates the view data.
  const SettingsViewData({
    this.cycle = const CycleSettings(),
    this.fertileWindowOptedIn = false,
  });

  /// The mode and its opt-in.
  final CycleSettings cycle;

  /// Whether the fertile window estimate is shown on the Today screen.
  final bool fertileWindowOptedIn;
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
    super.key,
  });

  /// The current settings.
  final SettingsViewData data;

  /// Called with the mode the user chose.
  final void Function(CycleMode mode)? onModeChanged;

  /// Called when she asks for estimates despite a mode that disables them.
  final void Function({required bool optedIn})? onPredictionsOptInChanged;

  /// Called when she turns the fertile window estimate on or off.
  final void Function({required bool optedIn})? onFertileWindowChanged;

  /// Called once she has confirmed erasing everything.
  final VoidCallback? onDeleteEverything;

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
              onChanged: onFertileWindowChanged == null
                  ? null
                  : (value) => onFertileWindowChanged!.call(optedIn: value),
              title: Text(l10n.showFertileWindow),
              // The caveat sits beside the switch, before the choice is made,
              // rather than only on the Today screen after it. Section 8 wants
              // it visible; the moment it matters most is here.
              subtitle: Text(l10n.fertileWindowCaveat),
              isThreeLine: true,
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
