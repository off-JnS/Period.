import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/fertile_window.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/logic/pregnancy_week.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/day_entry.dart';
import '../../l10n/app_localizations.dart';
import '../log/entry_icons.dart';
import '../log/entry_labels.dart';
import '../log/temperature.dart';
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
    this.pregnancy,
    this.today,
    this.countdown,
  });

  /// The day it is, shown as the date at the top. Null leaves the date out,
  /// as a test of one card alone does.
  final CycleDate? today;

  /// How far away the estimated window is, shown beside the date. Null when
  /// there is no window (docs/cycle-logic.md §3).
  final PeriodCountdown? countdown;

  /// In pregnancy mode, how far along -- or why that cannot be said. Null in
  /// every other mode.
  final PregnancyCount? pregnancy;

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
    // Each block slides up into place on arrival, one after another, so the
    // eye follows the page from the ring down.
    var order = 0;
    Widget enter(Widget child) => _Entrance(index: order++, child: child);

    // A grouped page scrolls rather than fitting a fixed column: at 200% text
    // size, or in German, this content is taller than a phone screen and must
    // not clip.
    return GroupedPage(
      title: l10n.todayTitle,
      children: [
        if (data.today case final today?)
          enter(_DateHeader(today: today, countdown: data.countdown)),
        const SizedBox(height: 16),
        enter(
          Center(
            child: switch (data.pregnancy) {
              PregnancyCounting(:final week) => PregnancyWeekRing(week: week),
              _ => CycleDayRing(
                day: data.cycleDay,
                expectedLength: data.typicalCycleLength,
              ),
            },
          ),
        ),
        if (data.pregnancy case final pregnancy?) ...[
          const SizedBox(height: 12),
          Text(
            switch (pregnancy) {
              PregnancyCounting() => l10n.pregnancyCountedFrom,
              PregnancyNeedsLastPeriod() => l10n.pregnancyNeedsLastPeriod,
              PregnancyCounterEnded() => l10n.pregnancyCounterEnded,
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.onAddEntry case final onAdd?) ...[
          const SizedBox(height: 24),
          // Labelled rather than an icon alone: a bare plus is guessable but
          // not readable, and section 9's refusal to let shape or colour carry
          // meaning on its own applies to an action as much as to a calendar
          // cell. The screen's one prominent button, as the HIG asks.
          enter(
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                onAdd();
              },
              icon: const Icon(CupertinoIcons.add),
              label: Text(l10n.addEntry),
            ),
          ),
        ],
        const SizedBox(height: 28),
        enter(_PredictionSection(prediction: data.prediction)),
        if (data.fertileWindow case final window?) ...[
          const SizedBox(height: 12),
          enter(_FertileWindowSection(window: window)),
        ],
        // Folds away rather than vanishing when dismissed.
        AnimatedSize(
          duration: _motion(context, const Duration(milliseconds: 250)),
          curve: Curves.easeOutCubic,
          child: data.showDoctorHint && !_hintDismissed
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _DoctorHint(
                    onDismiss: () => setState(() => _hintDismissed = true),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 12),
        enter(
          _LoggedTodaySection(
            entry: data.todayEntry,
            isPeriodStart: data.isTodayPeriodStart,
            onEdit: widget.onEditToday,
          ),
        ),
      ],
    );
  }
}

/// [duration], or none at all when the system asks for reduced motion.
Duration _motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Fades and slides [child] up into place once, when the screen appears,
/// a little after the block above it.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  static const _step = 70;
  static const _length = 420;

  @override
  void initState() {
    super.initState();
    final delay = widget.index * _step;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: delay + _length),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(delay / (delay + _length), 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _progress.value,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - _progress.value)),
        child: child,
      ),
    ),
  );
}

/// Today's date, with how far away the estimated window is beside it.
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.today, this.countdown});

  final CycleDate today;
  final PeriodCountdown? countdown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    final countdownText = switch (countdown) {
      CountdownUpcoming(:final fromDays, :final toDays) =>
        l10n.countdownUpcoming(fromDays, toDays),
      CountdownInWindow() => l10n.countdownInWindow,
      CountdownPastWindow() => l10n.countdownPastWindow,
      null => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            DateFormat.MMMMEEEEd(locale)
                .format(DateTime(today.year, today.month, today.day)),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (countdownText != null)
            Semantics(
              container: true,
              label: '${l10n.nextPeriodHeading}: $countdownText',
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.drop_fill,
                        size: 14,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          countdownText,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
        icon: CupertinoIcons.drop_fill,
        heading: l10n.nextPeriodHeading,
        body: l10n.estimatedRange(
          _formatDay(context, earliest),
          _formatDay(context, latest),
        ),
        bodyStyle: theme.textTheme.headlineMedium,
        footnote: l10n.estimatedFromYourEntries,
      ),
      NotEnoughCycles(:final have, :final need) => _InfoCard(
        icon: CupertinoIcons.hourglass,
        heading: l10n.nextPeriodHeading,
        body: l10n.needMoreCycles(need - have),
      ),
      CyclesTooVariable() => _InfoCard(
        icon: CupertinoIcons.waveform_path,
        heading: l10n.nextPeriodHeading,
        body: l10n.cyclesTooVariable,
      ),
      PredictionsDisabled(:final mode) => _InfoCard(
        icon: CupertinoIcons.pause_circle,
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
      icon: CupertinoIcons.sparkles,
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
      icon: CupertinoIcons.info_circle,
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

    final lines = entryLines(
      l10n,
      current,
      formatTemperature: (centi) => formatTemperature(
        centi,
        Localizations.localeOf(context).toLanguageTag(),
      ),
    );
    final hasAnything = isPeriodStart || lines.isNotEmpty;

    return SectionCard(
      icon: CupertinoIcons.square_pencil,
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
              _IconLine(
                icon: CupertinoIcons.drop_fill,
                text: l10n.periodStartSummary,
              ),
            for (final line in lines)
              _IconLine(icon: entryLineIcon(line.kind), text: line.text),
          ],
        ],
      ),
    );
  }
}

/// One logged thing, with its icon, as the calendar's day preview shows it.
class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
