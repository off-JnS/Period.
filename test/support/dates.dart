import 'package:period/domain/models/cycle_date.dart';

/// Builds a [CycleDate] for tests.
///
/// CLAUDE.md section 7 asks for builders rather than inline literals, so that
/// when the shape of a value type changes there is one place to follow.
CycleDate aDate(int year, int month, int day) => CycleDate(year, month, day);

/// A day that is not near any boundary, for tests that need "some date".
CycleDate anyDate() => aDate(2024, 5, 17);
