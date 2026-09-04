import 'package:freezed_annotation/freezed_annotation.dart';

import 'cycle_date.dart';
import 'symptom.dart';

part 'day_entry.freezed.dart';

/// How heavy the bleeding was on a day.
///
/// Recorded observation rather than interpretation: nothing in the app derives
/// meaning from these values yet. The scale is the conventional four-point one;
/// it is a product choice rather than a clinical one, and it is stored by name
/// so the set can grow without a migration.
enum FlowIntensity {
  /// Logged as a period day, but no bleeding.
  none,

  /// Light bleeding, e.g. spotting.
  light,

  /// Moderate bleeding.
  medium,

  /// Heavy bleeding.
  heavy,
}

/// Everything the user logged on one calendar day.
///
/// [date] is the identity; every other field is nullable, per CLAUDE.md section
/// 5 -- nobody logs everything every day, and an absent value means "not
/// recorded", never "zero" or "none".
///
/// Note what is *not* here: no cycle day number, no phase, no cycle length.
/// Section 4 computes all of those on read from the stored period start dates,
/// so putting any of them on an entry would create a second source of truth that
/// goes stale the moment the user corrects a date.
@freezed
abstract class DayEntry with _$DayEntry {
  const factory DayEntry({
    /// The calendar day this entry describes.
    required CycleDate date,

    /// How heavy the bleeding was, if the user recorded it.
    FlowIntensity? flow,

    /// The user's own note. Free text, never parsed.
    String? note,

    /// What the user logged on this day. Empty when nothing was.
    ///
    /// Required rather than defaulted so a caller cannot accidentally construct
    /// an entry that claims no symptoms when it simply has not loaded them.
    required Set<Symptom> symptoms,
  }) = _DayEntry;
}
