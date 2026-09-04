import '../models/cycle_date.dart';
import 'period_prediction.dart';

/// Shortest luteal phase used for the estimate, in days.
///
/// The luteal phase averages 12.4 days with a 95% CI of 7-17 (Bull et al.
/// 2019). This uses roughly one standard deviation rather than the full
/// interval: the full interval yields a window about 22 days wide, which is
/// honest and useless. That narrowing is a product judgement, not a finding.
const shortestLutealPhase = 10;

/// Longest luteal phase used for the estimate, in days.
const longestLutealPhase = 15;

/// How many days before ovulation are counted as fertile.
///
/// The fertile window is the six-day interval ending on the day of ovulation
/// (Wilcox et al. 2000): the five days before, plus the day itself.
const fertileDaysBeforeOvulation = 5;

/// An estimated fertile window.
///
/// Deliberately not called a "safe" or "unsafe" period, and never presented as
/// either. Section 8 forbids describing the app as suitable for contraception.
class FertileWindowEstimate {
  /// Creates the estimate.
  const FertileWindowEstimate({required this.earliest, required this.latest});

  /// First day of the estimated window.
  final CycleDate earliest;

  /// Last day of the estimated window, inclusive.
  final CycleDate latest;

  /// How many days the estimate spans, inclusive of both ends.
  int get spanInDays => earliest.daysUntil(latest) + 1;

  /// Whether [date] falls inside the estimate.
  bool contains(CycleDate date) =>
      !date.isBefore(earliest) && !date.isAfter(latest);
}

/// Estimates the fertile window by counting **backwards** from the predicted
/// period.
///
/// This is the whole reason the method is worth writing down. The phases are not
/// equally variable: the follicular phase has a 95% CI of 10-30 days, the luteal
/// 7-17 (Bull et al. 2019). Counting forwards from the last period — what nearly
/// every competing app does — runs the estimate through the wider one. Counting
/// backwards from the next predicted period runs it through the narrower.
///
/// The result inherits the uncertainty of [prediction] rather than being derived
/// from a single date: an estimate built on an estimate has to carry both, and
/// collapsing the first would launder uncertainty the user is entitled to see.
///
/// Returns null when there is no prediction to count back from, or when the user
/// has not opted in. It is off by default: this is the app's most misusable
/// feature and the one where the evidence for calendar methods is weakest.
FertileWindowEstimate? estimateFertileWindow({
  required PeriodPrediction prediction,
  required bool optedIn,
}) {
  if (!optedIn) return null;
  if (prediction is! PredictedPeriod) return null;

  // Earliest ovulation pairs the earliest the period might start with the
  // longest luteal phase; latest ovulation pairs the latest start with the
  // shortest. Both extremes, so the window covers the whole plausible range.
  final earliestOvulation = prediction.earliest.subtractDays(
    longestLutealPhase,
  );
  final latestOvulation = prediction.latest.subtractDays(shortestLutealPhase);

  return FertileWindowEstimate(
    earliest: earliestOvulation.subtractDays(fertileDaysBeforeOvulation),
    latest: latestOvulation,
  );
}
