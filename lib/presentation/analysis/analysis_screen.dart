import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/period_length.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/cycle.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../section_card.dart';

/// Everything the cycles screen needs, already computed.
///
/// All of it derived on read from the stored period starts, per section 4, and
/// none of it written back. A stored average would be wrong the moment the user
/// corrected a start date, which she does constantly.
class AnalysisViewData {
  /// Creates the view data.
  const AnalysisViewData({
    this.cycles = const [],
    this.eligible = const [],
    this.medianLength,
    this.shortest,
    this.longest,
    this.statisticsVisible = true,
    this.periodLengths = const {},
    this.usualPeriodLength,
    this.knownPeriodCount = 0,
  });

  /// How long each period lasted, by its start day. Missing means not worked
  /// out; see [PeriodLength] for known, ongoing and unknown.
  final Map<CycleDate, PeriodLength> periodLengths;

  /// The median of the finished lengths, once there are enough.
  ///
  /// Shown in every mode, pregnancy included: a duration is description, not
  /// a statistic about cycles (docs/cycle-logic.md §1 and §6).
  final int? usualPeriodLength;

  /// How many finished lengths [usualPeriodLength] rests on.
  final int knownPeriodCount;

  /// Whether the length summaries and chart may be shown.
  ///
  /// False in pregnancy: docs/cycle-logic.md section 6 hides cycle statistics
  /// there rather than zeroing them. The history of recorded starts is pure
  /// description and stays.
  final bool statisticsVisible;

  /// Every cycle implied by the recorded starts, oldest first. The last may be
  /// in progress.
  final List<Cycle> cycles;

  /// The completed cycles of plausible length that the statistics rest on.
  final List<Cycle> eligible;

  /// The median length of [eligible], or null when there are too few.
  final int? medianLength;

  /// The shortest length among [eligible], in days.
  final int? shortest;

  /// The longest length among [eligible], in days.
  final int? longest;
}

/// The user's own cycle history, described back to her.
///
/// Section 8 governs every word here. This screen states what was recorded and
/// how much it varied; it does not call a cycle irregular, does not name a
/// condition, and does not tell her what any of it means about her.
class AnalysisScreen extends StatelessWidget {
  /// Creates the screen.
  const AnalysisScreen({required this.data, this.onShareReport, super.key});

  /// The history to render.
  final AnalysisViewData data;

  /// Makes and shares the PDF report, given where the tap was (the iPad
  /// share popover points at it). Null hides the row.
  final void Function(Rect? origin)? onShareReport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GroupedPage(
      title: l10n.analysisTitle,
      children: data.cycles.isEmpty
          ? [_Empty(message: l10n.nothingToSummariseYet)]
          : [
              if (!data.statisticsVisible) ...[
                SectionCard(
                  icon: Icons.visibility_off_outlined,
                  heading: l10n.modePregnancy,
                  child: Text(
                    l10n.statisticsHiddenInPregnancy,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 28),
              ] else ...[
                _Statistics(data: data),
                const SizedBox(height: 12),
              ],
              _PeriodLength(data: data),
              const SizedBox(height: 12),
              if (data.statisticsVisible && data.eligible.length >= 2) ...[
                _LengthChart(cycles: data.eligible),
                const SizedBox(height: 28),
              ],
              _History(cycles: data.cycles, lengths: data.periodLengths),
              if (onShareReport case final share?) ...[
                const SizedBox(height: 28),
                _ShareReport(onShare: share),
              ],
            ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.insights_outlined,
                  size: 32,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Statistics extends StatelessWidget {
  const _Statistics({required this.data});

  final AnalysisViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final median = data.medianLength;

    // Too little history is a state with something to say, not a blank. The
    // number needed matches what prediction asks for, so the two screens do not
    // give the user different accounts of how much is enough.
    if (median == null) {
      final have = data.eligible.length;
      return SectionCard(
        icon: Icons.timelapse_outlined,
        heading: l10n.typicalLengthHeading,
        child: Text(
          l10n.needMoreForStatistics(cyclesNeededToPredict - have),
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    final shortest = data.shortest;
    final longest = data.longest;

    final typical = SectionCard(
      icon: Icons.timelapse_outlined,
      heading: l10n.typicalLengthHeading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lengthInDays(median), style: theme.textTheme.headlineLarge),
          const SizedBox(height: 4),
          Text(
            l10n.basedOnCycles(data.eligible.length),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (shortest == null || longest == null) return typical;

    final variation = SectionCard(
      icon: Icons.straighten_outlined,
      heading: l10n.variationHeading,
      child: Text(
        shortest == longest
            ? l10n.variationSteady
            : l10n.variationRange(shortest, longest),
        style: theme.textTheme.bodyLarge,
      ),
    );

    // Side by side when there is room; stacked at large text sizes, where two
    // columns would squeeze each figure into a sliver.
    final roomy = MediaQuery.textScalerOf(context).scale(1) <= 1.2;
    if (!roomy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [typical, const SizedBox(height: 16), variation],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: typical),
          const SizedBox(width: 12),
          Expanded(child: variation),
        ],
      ),
    );
  }
}

/// A bar per completed cycle, oldest to newest.
///
/// Every bar is labelled with its own number, so the chart is a second way of
/// reading the figures rather than the only way: length alone would put this in
/// the same category as colour alone, which section 9 rules out.
class _LengthChart extends StatelessWidget {
  const _LengthChart({required this.cycles});

  final List<Cycle> cycles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final lengths = [for (final cycle in cycles) ?cycle.lengthInDays];
    if (lengths.isEmpty) return const SizedBox.shrink();

    final longest = lengths.reduce((a, b) => a > b ? a : b);

    return SectionCard(
      icon: Icons.bar_chart_rounded,
      heading: l10n.cycleLengthsHeading,
      child: Semantics(
        label: l10n.cycleLengthChartLabel,
        child: Column(
          children: [
            for (final length in lengths)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: AlignmentDirectional.centerStart,
                        // Scaled against the longest recorded cycle rather
                        // than against 28: the comparison that means anything
                        // is with her own other cycles.
                        child: FractionallySizedBox(
                          widthFactor: length / longest,
                          heightFactor: 1,
                          child: DecoratedBox(
                            // Solid, as in Apple's own charts: the bar's
                            // length is the data and nothing should compete.
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 64,
                      child: Text(
                        l10n.lengthInDays(length),
                        textAlign: TextAlign.end,
                        // Equal-width digits, so a column of lengths lines up.
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodLength extends StatelessWidget {
  const _PeriodLength({required this.data});

  final AnalysisViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final usual = data.usualPeriodLength;

    return SectionCard(
      icon: Icons.water_drop_outlined,
      heading: l10n.usualPeriodLengthHeading,
      child: usual == null
          ? Text(l10n.needFlowForPeriodLength, style: theme.textTheme.bodyLarge)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.lengthInDays(usual),
                  style: theme.textTheme.headlineLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.basedOnPeriods(data.knownPeriodCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.cycles, this.lengths = const {}});

  final List<Cycle> cycles;
  final Map<CycleDate, PeriodLength> lengths;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    // Newest first: the recent cycles are the ones anyone opens this to check.
    final newestFirst = cycles.reversed.toList();

    // An inset grouped list, as in Settings: heading outside, rows inside,
    // hairlines inset from the leading edge.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(l10n.historyHeading),
        Card(
          child: Column(
            children: [
              for (final (index, cycle) in newestFirst.indexed) ...[
                if (index > 0) const Divider(indent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.cycleStartedOn(
                                _formatDay(locale, cycle.start),
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                            // Unknown lengths say nothing rather than "0".
                            if (switch (lengths[cycle.start]) {
                                  KnownPeriodLength(:final days) =>
                                    l10n.periodLastedInHistory(days),
                                  OngoingPeriodLength(:final daysSoFar) =>
                                    l10n.periodOngoingInHistory(daysSoFar),
                                  _ => null,
                                }
                                case final line?)
                              Text(
                                line,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      switch (cycle.lengthInDays) {
                        final length? => Text(
                          l10n.lengthInDays(length),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        // Spelled out rather than defaulted: an in-progress cycle
                        // has no length yet, and rendering a blank there would
                        // read as missing data instead of an unfinished cycle.
                        null => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: ShapeDecoration(
                            shape: const StadiumBorder(),
                            color: theme.colorScheme.primaryContainer,
                          ),
                          child: Text(
                            l10n.cycleInProgress,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      },
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDay(String locale, CycleDate date) =>
    DateFormat.yMMMd(locale).format(DateTime(date.year, date.month, date.day));

class _ShareReport extends StatelessWidget {
  const _ShareReport({required this.onShare});

  final void Function(Rect? origin) onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Builder(
            builder: (context) => InkWell(
              onTap: () {
                final box = context.findRenderObject() as RenderBox?;
                onShare(
                  box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.ios_share_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.shareReport,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        GroupFooter(l10n.shareReportFooter),
      ],
    );
  }
}
