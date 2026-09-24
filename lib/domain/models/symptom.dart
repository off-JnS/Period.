import 'package:freezed_annotation/freezed_annotation.dart';

part 'symptom.freezed.dart';

/// Something the user logged on a day, identified by a stable string key.
///
/// The key is the whole model, and that is deliberate. CLAUDE.md section 5
/// requires symptoms to be a many-to-many keyed by string rather than fixed
/// columns, so that adding a symptom never requires a migration. Storing a key
/// rather than an id keeps that promise: a new symptom is a new string.
///
/// There is no display name here. Section 8 puts every user-facing string in the
/// ARB files, so the key is looked up for display in the presentation layer and
/// translated per locale. A name stored in the database would be a German user's
/// English label forever.
@freezed
abstract class Symptom with _$Symptom {
  const factory Symptom({
    /// Stable identifier, e.g. `cramps`. Never shown to the user as-is.
    required String key,
  }) = _Symptom;
}

/// The symptoms the app offers as chips, in the order they are shown.
///
/// A list in code rather than a table in the database, deliberately. Section 5
/// requires that adding a symptom never needs a migration, and a catalogue table
/// would need one every time this list grows. Stored rows reference these keys
/// by string, so a key that disappears from this list still reads back from the
/// database as a [Symptom] -- the entry survives its chip being retired.
///
/// The keys are stable identifiers and are never shown to the user. Each has a
/// matching ARB string looked up in the presentation layer; adding one here
/// without adding its translation is a missing label, not a crash.
const offeredSymptomKeys = <String>[
  'cramps',
  'headache',
  'backache',
  'bloating',
  'fatigue',
  'nausea',
  'tenderBreasts',
  'moodChange',
  'acne',
  'troubleSleeping',
];
