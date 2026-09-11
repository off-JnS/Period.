import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/logic/logged_summary.dart';
import '../../l10n/app_localizations.dart';
import '../symptom_labels.dart';

/// One completed cycle, ready to draw.
class CycleSummary {
  /// Creates the summary.
  const CycleSummary({
    required this.startedOn,
    required this.lengthInDays,
    required this.periodDays,
  });

  /// The day the period started.
  final DateTime startedOn;

  /// How long the cycle ran.
  final int lengthInDays;

  /// How many consecutive days of flow were recorded, per
  /// docs/cycle-logic.md section 1. Zero when she marked a start without
  /// logging any.
  final int periodDays;
}

/// Everything the analysis screen shows, already computed.
class AnalysisViewData {
  /// Creates the view data.
  const AnalysisViewData({
    this.cycles = const [],
    this.symptoms = const [],
    this.daysLogged = 0,
    this.typicalLength,
    this.shortestLength,
    this.longestLength,
    this.typicalPeriodDays,
  });

  /// Completed cycles, oldest first.
  final List<CycleSummary> cycles;

  /// Symptoms she has logged, most frequent first.
  final List<SymptomTally> symptoms;

  /// How many days have anything recorded on them.
  final int daysLogged;

  /// The median cycle length, or null without enough history.
  final int? typicalLength;

  /// The shortest and longest completed cycles.
  final int? shortestLength;
  final int? longestLength;

  /// The median period duration, or null when none was ever recorded.
  final int? typicalPeriodDays;

  /// Whether there is anything at all to show.
  bool get isEmpty => cycles.isEmpty && symptoms.isEmpty && daysLogged == 0;
}

/// What she has actually logged, and nothing else.
///
/// The one screen in this app that never predicts. docs/cycle-logic.md section
/// 6 is explicit that pure description -- cycles logged, period durations --
/// may be shown in **every** cycle mode, including the ones where estimates are
/// off, so this screen is deliberately *not* gated on
/// [CycleSettings.predictionsEnabled].
///
/// That is the opposite of the fertile-window switch in settings, which is
/// disabled in those modes, and the two sit close enough together to look
/// contradictory. They are not: that switch turns on an estimate, and this
/// screen contains none.
///
/// A pure function of [data], like the other screens, so every state -- and the
/// thin ones matter most -- is a golden without a database.
class AnalysisScreen extends StatelessWidget {
  /// Creates the screen.
  const AnalysisScreen({required this.data, super.key});

  /// What to show.
  final AnalysisViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisTitle)),
      body: SafeArea(
        child: data.isEmpty
            ? _NothingYet()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _Summary(data: data),
                  if (data.cycles.length >= 2) ...[
                    const SizedBox(height: 24),
                    _SectionHeading(l10n.cycleLengthsHeading),
                    _CycleLengthChart(cycles: data.cycles),
                  ],
                  if (data.cycles.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeading(l10n.cycleByCycleHeading),
                    // The chart's values, in words. Section 9 forbids
                    // information carried by shape alone, and a bar whose
                    // height is the only place a number lives is exactly that.
                    _CycleList(cycles: data.cycles),
                  ],
                  if (data.symptoms.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeading(l10n.symptomsLoggedHeading),
                    _SymptomList(
                      symptoms: data.symptoms,
                      daysLogged: data.daysLogged,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// The headline numbers.
class _Summary extends StatelessWidget {
  const _Summary({required this.data});

  final AnalysisViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final typical = data.typicalLength;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (typical == null)
          Text(l10n.notEnoughCyclesYet, style: theme.textTheme.bodyMedium)
        else ...[
          Text(l10n.typicalCycleLength, style: theme.textTheme.labelLarge),
          Text(l10n.daysCount(typical), style: theme.textTheme.headlineMedium),
          if (data.shortestLength != null && data.longestLength != null)
            Text(
              l10n.rangeOfLengths(data.shortestLength!, data.longestLength!),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _Stat(label: l10n.cyclesRecorded, value: '${data.cycles.length}'),
            _Stat(label: l10n.daysLogged, value: '${data.daysLogged}'),
            if (data.typicalPeriodDays != null)
              _Stat(
                label: l10n.typicalPeriodLength,
                value: l10n.daysCount(data.typicalPeriodDays!),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// How many days apart the chart's horizontal lines and left-hand labels are.
///
/// Seven, so the unit is a week and one of the lines lands on 28 -- the number
/// everyone has been told a cycle is. It is a landmark to read the bars
/// against, not a target: docs/cycle-logic.md section 0 is explicit that only
/// about 13% of cycles are 28 days, and nothing here marks it as normal.
const _axisIntervalDays = 7.0;

/// One bar per completed cycle.
///
/// A single series, so there is no categorical palette to validate and no
/// legend to draw -- the heading names what the bars are. Deliberately no trend
/// line and no projection: section 8 forbids implying a direction, and a line
/// sloping off the right-hand edge is a prediction whatever the axis is called.
///
/// The numbers live in the list below rather than on every bar, which keeps the
/// chart readable and still satisfies section 9.
class _CycleLengthChart extends StatelessWidget {
  const _CycleLengthChart({required this.cycles});

  final List<CycleSummary> cycles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lengths = [for (final cycle in cycles) cycle.lengthInDays];
    final tallest = lengths.reduce((a, b) => a > b ? a : b);

    return Semantics(
      // The chart itself says nothing to a screen reader. The list beneath it
      // carries every value, so this is labelled as a picture of them rather
      // than left as an unexplained blank.
      label: l10n.cycleLengthChartDescription(cycles.length),
      excludeSemantics: true,
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: (tallest + 4).toDouble(),
            // Recessive: the data is the ink, the frame is not. The grid is
            // horizontal only and one shade off the surface, and it is solid --
            // a dashed grid reads as a projection or a threshold when it is
            // only a grid.
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: _axisIntervalDays,
              getDrawingHorizontalLine: (value) => FlLine(
                color: theme.colorScheme.outlineVariant,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            // No tooltip. On a touch device it would need a tap to appear, and
            // every value is already written out in the list below the chart,
            // which is also what a screen reader is given.
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: _axisIntervalDays,
                  // Scaled for the same reason the bottom strip is: a fixed
                  // width clips the numbers at a larger text size.
                  reservedSize: MediaQuery.textScalerOf(context).scale(28),
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${value.toInt()}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  // Follows the text rather than a fixed 22: at a larger text
                  // size a fixed strip clips the numbers off at the bottom,
                  // which is the same failure the calendar's day circles had.
                  reservedSize: MediaQuery.textScalerOf(context).scale(22),
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${value.toInt() + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < cycles.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: cycles[i].lengthInDays.toDouble(),
                      color: theme.colorScheme.primary,
                      width: 14,
                      // Rounded at the data end, square on the baseline.
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every cycle's numbers, in words.
class _CycleList extends StatelessWidget {
  const _CycleList({required this.cycles});

  final List<CycleSummary> cycles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    return Column(
      children: [
        for (final cycle in cycles.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    materialL10n.formatMediumDate(cycle.startedOn),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  l10n.daysCount(cycle.lengthInDays),
                  style: theme.textTheme.bodyMedium,
                ),
                if (cycle.periodDays > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    l10n.bleedingDays(cycle.periodDays),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

/// How often each symptom was logged.
class _SymptomList extends StatelessWidget {
  const _SymptomList({required this.symptoms, required this.daysLogged});

  final List<SymptomTally> symptoms;
  final int daysLogged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final most = symptoms.first.days;

    return Column(
      children: [
        for (final tally in symptoms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    symptomLabel(l10n, tally.symptom.key),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: tally.days / most,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.daysCount(tally.days),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Before there is anything to analyse.
///
/// The state most likely to look broken, and the one a new user sees first.
class _NothingYet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insights_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.nothingToAnalyseYet,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.nothingToAnalyseYetDetail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
