import 'package:period/domain/models/cycle.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/domain/models/symptom.dart';

import 'dates.dart';

/// Builders for model test data, per CLAUDE.md section 7. Tests say what they
/// are varying and inherit the rest, so adding a field to a model does not mean
/// editing every test that happens to construct one.

/// A symptom with a stable key.
Symptom aSymptom({String key = 'cramps'}) => Symptom(key: key);

/// A day entry. Defaults to a bare one: a date and nothing else recorded, which
/// is the common case section 5 describes.
DayEntry aDayEntry({
  CycleDate? date,
  FlowIntensity? flow,
  String? note,
  Set<Symptom>? symptoms,
}) => DayEntry(
  date: date ?? anyDate(),
  flow: flow,
  note: note,
  symptoms: symptoms ?? const <Symptom>{},
);

/// A cycle. Defaults to a completed 28-day one; pass `end: null` explicitly via
/// [inProgress] for the current cycle.
Cycle aCycle({CycleDate? start, CycleDate? end, bool inProgress = false}) {
  final from = start ?? aDate(2024, 1, 1);
  return Cycle(start: from, end: inProgress ? null : (end ?? from.addDays(27)));
}
