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
