import '../models/cycle_date.dart';
import '../models/cycle_mode.dart';
import 'cycle_analysis.dart';
import 'cycle_statistics.dart';

/// Fewest completed cycles before anything is predicted.
///
/// With fewer, the app says it cannot predict yet. It does **not** fall back to
/// 28 days: only about 13% of cycles are 28 days, and that assumption is the
/// source of the industry's inaccuracy rather than a safe default.
const cyclesNeededToPredict = 2;

/// Narrowest half-width of a prediction window, in days.
///
/// Never zero. Section 8 forbids stating a prediction as certainty, and no
/// cycle is certain, so even a metronomic user gets a range rather than a day.
const narrowestHalfWidth = 1;

/// Widest half-width still worth showing, in days.
///
/// Past this the estimate has stopped being useful, and the honest answer is to
/// say the cycles are too variable rather than draw a two-week band and call it
/// a prediction.
const widestUsefulHalfWidth = 7;

/// The outcome of trying to predict the next period.
///
/// A sealed type rather than a nullable window, so that every reason for having
/// no prediction is explicit and the UI is forced to say *which* it is. Section
/// 10 requires "predictions are off" to be first-class, and section 8's honesty
/// requirements mean "not enough data" and "too variable" have to be
/// distinguishable to the user as well.
sealed class PeriodPrediction {
  const PeriodPrediction();
}

/// The user's cycle mode disables prediction.
class PredictionsDisabled extends PeriodPrediction {
  /// Creates the result.
  const PredictionsDisabled(this.mode);

  /// The mode responsible, so the UI can explain rather than just show nothing.
  final CycleMode mode;
}

/// Too few completed cycles so far.
class NotEnoughCycles extends PeriodPrediction {
  /// Creates the result.
  const NotEnoughCycles({required this.have, required this.need});

  /// How many usable completed cycles exist.
  final int have;

  /// How many are needed.
  final int need;
}

/// The cycles vary too much for a window to mean anything.
class CyclesTooVariable extends PeriodPrediction {
  /// Creates the result.
  const CyclesTooVariable(this.halfWidthDays);

  /// The half-width that would have been required, in days.
  final int halfWidthDays;
}

/// A predicted window for the next period.
class PredictedPeriod extends PeriodPrediction {
  /// Creates the result.
  const PredictedPeriod({required this.earliest, required this.latest});

  /// First day of the window.
  final CycleDate earliest;

  /// Last day of the window, inclusive.
  final CycleDate latest;

  /// How many days the window spans, inclusive of both ends.
  int get spanInDays => earliest.daysUntil(latest) + 1;

  /// Whether [date] falls inside the window.
  bool contains(CycleDate date) =>
      !date.isBefore(earliest) && !date.isAfter(latest);
}

/// Estimates when the next period is likely to begin.
///
/// Takes the period start dates the user recorded and returns why there is no
/// prediction, or a window. See docs/cycle-logic.md section 3.
PeriodPrediction predictNextPeriod({
  required Iterable<CycleDate> periodStarts,
  CycleSettings settings = const CycleSettings(),
}) {
  if (!settings.predictionsEnabled) {
    return PredictionsDisabled(settings.mode);
  }

  final all = cyclesFrom(periodStarts);
  final eligible = eligibleForStatistics(all);
  if (eligible.length < cyclesNeededToPredict) {
    return NotEnoughCycles(
      have: eligible.length,
      need: cyclesNeededToPredict,
    );
  }

  final median = medianCycleLength(eligible)!;
  final spread = cycleLengthSpread(eligible)!;

  final halfWidth = spread.round() < narrowestHalfWidth
      ? narrowestHalfWidth
      : spread.round();
  if (halfWidth > widestUsefulHalfWidth) {
    return CyclesTooVariable(halfWidth);
  }

  // The window hangs off the most recent start the user actually recorded, not
  // off the last completed cycle -- otherwise an in-progress cycle would be
  // ignored and the prediction would be a month stale.
  final lastStart = all.last.start;
  final centre = lastStart.addDays(median.round());
  return PredictedPeriod(
    earliest: centre.subtractDays(halfWidth),
    latest: centre.addDays(halfWidth),
  );
}

/// Convenience for the common case of asking only whether a prediction exists.
PredictedPeriod? predictedWindowOrNull(PeriodPrediction prediction) =>
    prediction is PredictedPeriod ? prediction : null;
