import '../../domain/models/day_entry.dart';
import '../../domain/models/symptom.dart';
import '../../l10n/app_localizations.dart';

/// The display name for any logged key -- a symptom, a mood, discharge, sex or
/// the pill -- or null when this build has none.
///
/// Returns null rather than the key itself on purpose. The key is a stable
/// database identifier such as `tenderBreasts`, and `Symptom` is explicit that
/// it is never shown to the user as-is; a retired or newer key should disappear
/// from the UI rather than surface as raw camel case in the middle of German.
///
/// Callers skip what they cannot name. The row stays in the database either
/// way: nothing here deletes anything.
String? symptomLabel(AppLocalizations l10n, String key) => switch (key) {
  'cramps' => l10n.symptomCramps,
  'headache' => l10n.symptomHeadache,
  'backache' => l10n.symptomBackache,
  'bloating' => l10n.symptomBloating,
  'fatigue' => l10n.symptomFatigue,
  'nausea' => l10n.symptomNausea,
  'tenderBreasts' => l10n.symptomTenderBreasts,
  'moodChange' => l10n.symptomMoodChange,
  'acne' => l10n.symptomAcne,
  'troubleSleeping' => l10n.symptomTroubleSleeping,
  'mood.calm' => l10n.moodCalm,
  'mood.happy' => l10n.moodHappy,
  'mood.energetic' => l10n.moodEnergetic,
  'mood.sensitive' => l10n.moodSensitive,
  'mood.sad' => l10n.moodSad,
  'mood.anxious' => l10n.moodAnxious,
  'mood.irritable' => l10n.moodIrritable,
  'mood.lowEnergy' => l10n.moodLowEnergy,
  'discharge.none' => l10n.dischargeNone,
  'discharge.dry' => l10n.dischargeDry,
  'discharge.sticky' => l10n.dischargeSticky,
  'discharge.creamy' => l10n.dischargeCreamy,
  'discharge.watery' => l10n.dischargeWatery,
  'discharge.eggWhite' => l10n.dischargeEggWhite,
  'sex.none' => l10n.sexNone,
  'sex.protected' => l10n.sexProtected,
  'sex.unprotected' => l10n.sexUnprotected,
  pillTakenKey => l10n.pillTaken,
  'ovulationTest.negative' => l10n.ovulationTestNegative,
  'ovulationTest.positive' => l10n.ovulationTestPositive,
  'pregnancyTest.negative' => l10n.pregnancyTestNegative,
  'pregnancyTest.positive' => l10n.pregnancyTestPositive,
  _ => null,
};

/// The display name for a recorded flow intensity.
///
/// Spelled out per case rather than defaulted, so adding a value to
/// [FlowIntensity] is a compile error here instead of a silently missing label.
String flowLabel(AppLocalizations l10n, FlowIntensity flow) => switch (flow) {
  FlowIntensity.none => l10n.flowNone,
  FlowIntensity.light => l10n.flowLight,
  FlowIntensity.medium => l10n.flowMedium,
  FlowIntensity.heavy => l10n.flowHeavy,
};

/// What kind of thing an [EntryLine] reports, so a caller can put an icon
/// beside it.
enum EntryLineKind {
  /// The flow.
  flow,

  /// Symptoms.
  symptoms,

  /// Moods.
  mood,

  /// Discharge.
  discharge,

  /// Sex.
  sex,

  /// The pill.
  pill,

  /// Basal temperature.
  temperature,

  /// An ovulation test.
  ovulationTest,

  /// A pregnancy test.
  pregnancyTest,

  /// Her note, word for word.
  note,
}

/// One line describing part of a logged day.
typedef EntryLine = ({EntryLineKind kind, String text});

/// Everything in [entry] she can read back, one line per kind, in the order
/// the log sheet asks for them. The period start is left to the caller, which
/// knows whether to call it "today".
///
/// Keys this build cannot name are skipped rather than shown raw; see
/// [symptomLabel]. Nothing here deletes them.
List<EntryLine> entryLines(
  AppLocalizations l10n,
  DayEntry? entry, {
  required String Function(int centiCelsius) formatTemperature,
}) {
  if (entry == null) return const [];
  final keys = {for (final symptom in entry.symptoms) symptom.key};

  // One line per kind, each in its offered order rather than alphabetical,
  // so moods read as a mood list and not mixed in among symptoms.
  List<String> named(Iterable<String> offered) => [
    for (final key in offered)
      if (keys.contains(key)) ?symptomLabel(l10n, key),
  ];
  // Symptoms include keys this build no longer offers but can still name.
  final namespaced = {
    ...offeredMoodKeys,
    ...offeredDischargeKeys,
    ...offeredSexKeys,
    ...offeredOvulationTestKeys,
    ...offeredPregnancyTestKeys,
    pillTakenKey,
  };
  final symptoms = <String>[
    for (final key in keys)
      if (!namespaced.contains(key)) ?symptomLabel(l10n, key),
  ]..sort();
  final moods = named(offeredMoodKeys);
  final discharge = named(offeredDischargeKeys);
  final sex = named(offeredSexKeys);
  final ovulationTest = named(offeredOvulationTestKeys);
  final pregnancyTest = named(offeredPregnancyTestKeys);

  return [
    if (entry.flow case final flow?)
      (kind: EntryLineKind.flow, text: l10n.flowSummary(flowLabel(l10n, flow))),
    if (symptoms.isNotEmpty)
      (kind: EntryLineKind.symptoms, text: symptoms.join(', ')),
    if (moods.isNotEmpty)
      (kind: EntryLineKind.mood, text: l10n.moodSummary(moods.join(', '))),
    if (discharge.isNotEmpty)
      (
        kind: EntryLineKind.discharge,
        text: l10n.dischargeSummary(discharge.first),
      ),
    if (sex.isNotEmpty)
      (kind: EntryLineKind.sex, text: l10n.sexSummary(sex.first)),
    if (keys.contains(pillTakenKey))
      (kind: EntryLineKind.pill, text: l10n.pillTaken),
    if (entry.temperatureCentiCelsius case final centi?)
      (
        kind: EntryLineKind.temperature,
        text: l10n.temperatureSummary(formatTemperature(centi)),
      ),
    if (ovulationTest.isNotEmpty)
      (
        kind: EntryLineKind.ovulationTest,
        text: l10n.ovulationTestSummary(ovulationTest.first),
      ),
    if (pregnancyTest.isNotEmpty)
      (
        kind: EntryLineKind.pregnancyTest,
        text: l10n.pregnancyTestSummary(pregnancyTest.first),
      ),
    if (entry.note case final note? when note.isNotEmpty)
      (kind: EntryLineKind.note, text: note),
  ];
}
