import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_controls.dart';
import '../grouped_page.dart';

/// The cycle mode list and the switches that depend on it.
///
/// Every mode explains itself, including why estimates are off where they
/// are: section 10 treats "predictions off" as a state to be stated, not an
/// absence to be noticed.
class CycleModeSection extends StatelessWidget {
  /// Creates the section.
  const CycleModeSection({
    required this.settings,
    required this.onChanged,
    super.key,
  });

  /// What is currently chosen.
  final CycleSettings settings;

  /// Called with the whole new settings whenever she changes anything.
  final ValueChanged<CycleSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    void change(CycleSettings next) {
      HapticFeedback.selectionClick();
      onChanged(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(l10n.cycleModeHeading),
        CheckList(
          options: CycleMode.values,
          selected: settings.mode,
          label: (mode) => modeLabel(l10n, mode),
          icon: modeIcon,
          onSelected: (mode) => change(settings.copyWith(mode: mode)),
        ),
        GroupFooter(modeFooter(l10n, settings.mode)),
        // Grows and shrinks as the switches come and go, rather than letting
        // everything below jump.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (settings.mode == CycleMode.perimenopause) ...[
                const SizedBox(height: 28),
                SwitchGroup(
                  title: l10n.showEstimatesAnyway,
                  value: settings.predictionsOptedIn,
                  onChanged: (value) =>
                      change(settings.copyWith(predictionsOptedIn: value)),
                  footer: l10n.showEstimatesAnywayFooter,
                ),
              ],
              // Offered only where there is a period estimate to count back
              // from. In any other mode the switch would do nothing, and a
              // control that does nothing reads as broken.
              if (settings.predictionsEnabled) ...[
                const SizedBox(height: 28),
                SwitchGroup(
                  title: l10n.fertileWindowHeading,
                  value: settings.fertileWindowOptedIn,
                  onChanged: (value) async {
                    // Turning it on shows the caveat first, as a dialog she
                    // has to answer: the calendar draws the window without
                    // repeating it, so this is where it has to land.
                    if (value && !await _confirmFertileWindow(context)) {
                      return;
                    }
                    change(settings.copyWith(fertileWindowOptedIn: value));
                  },
                  // Section 8: the caveat also sits beside the switch,
                  // visible before she turns it on, never behind a tap.
                  footer: l10n.fertileWindowCaveat,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The icon beside [mode].
IconData modeIcon(CycleMode mode) => switch (mode) {
  CycleMode.natural => CupertinoIcons.arrow_2_circlepath,
  CycleMode.hormonalContraception => CupertinoIcons.capsule,
  CycleMode.pregnancy => CupertinoIcons.heart,
  CycleMode.perimenopause => CupertinoIcons.leaf_arrow_circlepath,
};

/// The display name of [mode].
String modeLabel(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.natural => l10n.modeNatural,
  CycleMode.hormonalContraception => l10n.modeHormonalContraception,
  CycleMode.pregnancy => l10n.modePregnancy,
  CycleMode.perimenopause => l10n.modePerimenopause,
};

/// Why [mode] does or does not show estimates.
String modeFooter(AppLocalizations l10n, CycleMode mode) => switch (mode) {
  CycleMode.natural => l10n.modeNaturalFooter,
  CycleMode.hormonalContraception => l10n.modeContraceptionFooter,
  CycleMode.pregnancy => l10n.modePregnancyFooter,
  CycleMode.perimenopause => l10n.modePerimenopauseFooter,
};

/// Asks before the fertile window is turned on, stating what it is not.
Future<bool> _confirmFertileWindow(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(l10n.fertileWindowHeading),
      content: Text(l10n.fertileWindowCaveat),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.fertileWindowTurnOn),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
