import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/symptom.dart';
import '../../l10n/app_localizations.dart';
import '../log/entry_labels.dart';
import '../section_card.dart';
import '../grouped_page.dart';
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
    this.todayEntry,
    this.isTodayPeriodStart = false,
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

  /// What the user logged for today, or null if she logged nothing.
  final DayEntry? todayEntry;

  /// Whether today is marked as a period start.
  ///
  /// Separate from [todayEntry] because that is how it is stored: a period start
  /// is its own row, not a field on an entry. A day can be a period start with
  /// no entry at all, and the summary has to say so.
  final bool isTodayPeriodStart;
}

/// The app's home: where the user is in her cycle, and what is estimated next.
class TodayScreen extends StatefulWidget {
  /// Creates the screen.
  const TodayScreen({
    required this.data,
    this.onAddEntry,
    this.onEditToday,
    super.key,
  });

  /// The already-computed state to render.
  final TodayViewData data;

  /// Opens the logging screen for a new day.
  ///
  /// Null hides the button entirely rather than showing a dead one. That is what
  /// a widget test rendering the screen in isolation gets.
  final VoidCallback? onAddEntry;

  /// Opens today's existing entry for correction.
  final VoidCallback? onEditToday;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool _hintDismissed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = widget.data;

    // A grouped page scrolls rather than fitting a fixed column: at 200% text
    // size, or in German, this content is taller than a phone screen and must
    // not clip.
    return GroupedPage(
      title: l10n.todayTitle,
      children: [
        const SizedBox(height: 8),
        Center(
          child: CycleDayRing(
            day: data.cycleDay,
            expectedLength: data.typicalCycleLength,
          ),
        ),
        if (widget.onAddEntry case final onAdd?) ...[
          const SizedBox(height: 24),
          // Labelled rather than an icon alone: a bare plus is guessable but
          // not readable, and section 9's refusal to let shape or colour carry
          // meaning on its own applies to an action as much as to a calendar
          // cell. The screen's one prominent button, as the HIG asks.
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              onAdd();
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addEntry),
          ),
        ],
        const SizedBox(height: 28),
        _PredictionSection(prediction: data.prediction),
        if (data.fertileWindow case final window?) ...[
          const SizedBox(height: 12),
          _FertileWindowSection(window: window),
        ],
        if (data.showDoctorHint && !_hintDismissed) ...[
          const SizedBox(height: 12),
          _DoctorHint(onDismiss: () => setState(() => _hintDismissed = true)),
        ],
        const SizedBox(height: 12),
        _LoggedTodaySection(
          entry: data.todayEntry,
          isPeriodStart: data.isTodayPeriodStart,
          onEdit: widget.onEditToday,
        ),
      ],
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
        icon: Icons.water_drop_rounded,
        heading: l10n.nextPeriodHeading,
        body: l10n.estimatedRange(
          _formatDay(context, earliest),
          _formatDay(context, latest),
        ),
        bodyStyle: theme.textTheme.headlineMedium,
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

    return SectionCard(
      icon: Icons.info_outline_rounded,
      heading: l10n.doctorHint,
      accent: theme.colorScheme.onSurface,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(onPressed: onDismiss, child: Text(l10n.dismiss)),
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

    return SectionCard(
      icon: icon,
      heading: heading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

/// What the user has recorded for today, with a way back in to change it.
///
/// Always present, including when nothing is logged. An empty day renders as
/// "nothing logged today" rather than as no card at all: the same reasoning as
/// [_PredictionSection], where showing nothing reads as a bug and leaves the
/// user unsure whether her entry saved.
class _LoggedTodaySection extends StatelessWidget {
  const _LoggedTodaySection({
    required this.entry,
    required this.isPeriodStart,
    this.onEdit,
  });

  final DayEntry? entry;
  final bool isPeriodStart;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = entry;

    // Symptoms this build has no name for are skipped rather than shown as raw
    // keys; see symptomLabel. The rows stay in the database untouched.
    final symptomNames = <String>[
      for (final symptom in current?.symptoms ?? const <Symptom>{})
        ?symptomLabel(l10n, symptom.key),
    ]..sort();

    final hasAnything =
        isPeriodStart ||
        current?.flow != null ||
        (current?.note?.isNotEmpty ?? false) ||
        symptomNames.isNotEmpty;

    return SectionCard(
      icon: Icons.edit_note_rounded,
      heading: l10n.loggedTodayHeading,
      trailing: onEdit == null
          ? null
          : TextButton(onPressed: onEdit, child: Text(l10n.edit)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasAnything)
            Text(l10n.nothingLoggedToday, style: theme.textTheme.bodyLarge)
          else ...[
            if (isPeriodStart)
              Text(l10n.periodStartSummary, style: theme.textTheme.bodyLarge),
            if (current?.flow case final flow?)
              Text(
                l10n.flowSummary(flowLabel(l10n, flow)),
                style: theme.textTheme.bodyLarge,
              ),
            if (symptomNames.isNotEmpty)
              Text(symptomNames.join(', '), style: theme.textTheme.bodyLarge),
            if (current?.note case final note? when note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(note, style: theme.textTheme.bodyMedium),
              ),
          ],
        ],
      ),
    );
  }
}
