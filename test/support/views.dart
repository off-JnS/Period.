import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/presentation/today/today_screen.dart';

import 'dates.dart';

/// Builders for presentation view data, per CLAUDE.md section 7.
///
/// Separate from `models.dart` because this one reaches Flutter, and that one
/// is imported by `test/domain`, which CI runs on the plain Dart VM to prove
/// section 2. Putting these two in one file made every domain test fail to
/// load while `flutter test` stayed green.

/// The Today screen's view data. Defaults to a fresh install: a real date, and
/// nothing logged yet.
///
/// A builder rather than the constructor, so that adding a field to
/// [TodayViewData] does not mean editing every test that happens to construct
/// one -- as [TodayViewData.today] would have, in thirty-odd places that do not
/// care what day it is.
TodayViewData aTodayView({
  CycleDate? today,
  int? cycleDay,
  int? typicalCycleLength,
  PeriodPrediction? prediction,
  FertileWindowEstimate? fertileWindow,
  bool showDoctorHint = false,
}) => TodayViewData(
  today: today ?? anyDate(),
  cycleDay: cycleDay,
  typicalCycleLength: typicalCycleLength,
  prediction:
      prediction ?? const NotEnoughCycles(have: 0, need: cyclesNeededToPredict),
  fertileWindow: fertileWindow,
  showDoctorHint: showDoctorHint,
);
