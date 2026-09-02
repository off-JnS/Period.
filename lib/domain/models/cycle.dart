import 'package:freezed_annotation/freezed_annotation.dart';

import 'cycle_date.dart';

part 'cycle.freezed.dart';

/// One cycle, derived from the period start dates the user recorded.
///
/// **This is never stored.** CLAUDE.md section 4 computes cycles on read from
/// the stored period start dates, every time, because users retroactively
/// correct those dates constantly and any persisted derivative is stale from
/// that moment on. There is no cycles table and there must not be one.
///
/// The model is deliberately thin. Length, phase, fertile window and whether a
/// cycle counts as irregular are all questions the medical specification
/// answers, and section 11 says that logic is specified in the project docs
/// rather than left to interpretation. Until those docs exist, this holds the
/// two facts that come straight from the data and nothing more.
@freezed
abstract class Cycle with _$Cycle {
  const Cycle._();

  const factory Cycle({
    /// The day the user marked this period as starting.
    required CycleDate start,

    /// The day before the next recorded period start, or null while this is the
    /// most recent cycle and no later start exists yet.
    CycleDate? end,
  }) = _Cycle;

  /// Whether this is the current cycle, with no later period start recorded.
  ///
  /// An in-progress cycle has no length yet, which is why so much of section 7's
  /// awkward-case list is about this state.
  bool get isInProgress => end == null;
}
