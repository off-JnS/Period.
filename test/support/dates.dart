import 'package:period/domain/models/cycle_date.dart';

/// Builds a [CycleDate] for tests.
///
/// CLAUDE.md section 7 asks for builders rather than inline literals, so that
/// when the shape of a value type changes there is one place to follow.
CycleDate aDate(int year, int month, int day) => CycleDate(year, month, day);

/// A day that is not near any boundary, for tests that need "some date".
CycleDate anyDate() => aDate(2024, 5, 17);

/// Period starts every [length] days, [count] of them, beginning at [from].
///
/// A builder rather than inline literals, per CLAUDE.md section 7, so a test
/// says how regular the user is instead of listing dates.
List<CycleDate> regularPeriodStarts({
  required CycleDate from,
  required int length,
  required int count,
}) {
  var day = from;
  final starts = <CycleDate>[];
  for (var i = 0; i < count; i++) {
    starts.add(day);
    day = day.addDays(length);
  }
  return starts;
}
