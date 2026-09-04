import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import 'cycle_day_ring.dart';

/// Everything the Today screen needs, already computed.
///
/// The screen takes results rather than raw entries so it stays a pure function
/// of its input: no database, no clock, and every state reachable in a test.
class TodayViewData {
  /// Creates the view data.
  const TodayViewData({
    required this.prediction,
    this.cycleDay,
    this.typicalCycleLength,
    this.fertileWindow,
    this.showDoctorHint = false,
  });

  /// The current cycle day, or null when nothing has been logged.
  final int? cycleDay;

  /// The user's typical cycle length, used only to fill the ring.
  final int? typicalCycleLength;

  /// Why there is no estimate, or the estimated window.
  final PeriodPrediction prediction;

  /// The fertile window estimate, when the user opted in and one exists.
  final FertileWindowEstimate? fertileWindow;

  /// Whether to offer the "might be worth mentioning to a doctor" hint.
  final bool showDoctorHint;
}

/// The app's home: where the user is in her cycle, and what is estimated next.
class TodayScreen extends StatefulWidget {
  /// Creates the screen.
  const TodayScreen({required this.data, super.key});

  /// The already-computed state to render.
  final TodayViewData data;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _hintDismissed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = widget.data;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayTitle)),
      body: SafeArea(
        // Scrollable rather than a fixed column: at 200% text size, or in
        // German, this content is taller than a phone screen and must not clip.
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          children: [
            Center(
              child: CycleDayRing(
                day: data.cycleDay,
                expectedLength: data.typicalCycleLength,
              ),
            ),
            const SizedBox(height: 32),
            _PredictionSection(prediction: data.prediction),
            if (data.fertileWindow case final window?) ...[
              const SizedBox(height: 24),
              _FertileWindowSection(window: window),
            ],
            if (data.showDoctorHint && !_hintDismissed) ...[
              const SizedBox(height: 24),
              _DoctorHint(
                onDismiss: () => setState(() => _hintDismissed = true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The next-period estimate, or an explanation of why there is not one.
///
/// Every branch says something. Showing nothing reads as a bug and invites the
/// user to conclude the app is broken, which is why section 10 asks for
/// predictions-off to be a state rather than an absence.
class _PredictionSection extends StatelessWidget {
  const _PredictionSection({required this.prediction});

  final PeriodPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return switch (prediction) {
      PredictedPeriod(:final earliest, :final latest) => _InfoCard(
        icon: Icons.calendar_today_outlined,
        heading: l10n.nextPeriodHeading,
        body: l10n.estimatedRange(
          _formatDay(context, earliest),
          _formatDay(context, latest),
        ),
        bodyStyle: theme.textTheme.headlineSmall,
        footnote: l10n.estimatedFromYourEntries,
      ),
      NotEnoughCycles(:final have, :final need) => _InfoCard(
        icon: Icons.more_horiz,
        heading: l10n.nextPeriodHeading,
        body: l10n.needMoreCycles(need - have),
      ),
      CyclesTooVariable() => _InfoCard(
        icon: Icons.show_chart,
        heading: l10n.nextPeriodHeading,
        body: l10n.cyclesTooVariable,
      ),
      PredictionsDisabled(:final mode) => _InfoCard(
        icon: Icons.pause_circle_outline,
        heading: l10n.nextPeriodHeading,
        body: switch (mode) {
          CycleMode.hormonalContraception => l10n.predictionsOffContraception,
          CycleMode.pregnancy => l10n.predictionsOffPregnancy,
          CycleMode.perimenopause => l10n.predictionsOffPerimenopause,
          // Unreachable: a natural cycle never disables predictions. Spelled out
          // rather than defaulted so adding a mode is a compile error here.
          CycleMode.natural => l10n.cyclesTooVariable,
        },
      ),
    };
  }
}

class _FertileWindowSection extends StatelessWidget {
  const _FertileWindowSection({required this.window});

  final FertileWindowEstimate window;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _InfoCard(
      icon: Icons.eco_outlined,
      heading: l10n.fertileWindowHeading,
      body: l10n.estimatedRange(
        _formatDay(context, window.earliest),
        _formatDay(context, window.latest),
      ),
      bodyStyle: Theme.of(context).textTheme.titleLarge,
      // Always visible, never behind a tap or a tooltip.
      footnote: l10n.fertileWindowCaveat,
    );
  }
}

class _DoctorHint extends StatelessWidget {
  const _DoctorHint({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.doctorHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onDismiss,
                child: Text(l10n.dismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled block of information.
///
/// Every state gets an icon as well as its text, so the states are told apart by
/// shape and wording rather than by colour — section 9.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.heading,
    required this.body,
    this.bodyStyle,
    this.footnote,
  });

  final IconData icon;
  final String heading;
  final String body;
  final TextStyle? bodyStyle;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                // Flexible so a longer German heading wraps instead of
                // overflowing.
                Flexible(
                  child: Text(
                    heading,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: bodyStyle ?? theme.textTheme.bodyLarge),
            if (footnote case final note?) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Formats one day for display in the reader's locale.
///
/// Display formatting only. [CycleDate.toIso8601] is for storage; a user should
/// never be shown a date in a format chosen for a database.
String _formatDay(BuildContext context, CycleDate date) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  // A DateTime purely as an argument to the formatter, never stored and never
  // returned. Section 3 keeps timestamps out of the model, not out of intl.
  return DateFormat.MMMd(locale)
      .format(DateTime(date.year, date.month, date.day));
}
