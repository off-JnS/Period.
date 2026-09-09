import '../l10n/app_localizations.dart';

/// Translates a stored symptom key for display.
///
/// An unknown key falls back to the key itself rather than crashing: a database
/// restored from a newer version of the app may contain symptoms this build has
/// never heard of, and showing something is better than losing her data.
String symptomLabel(AppLocalizations l10n, String key) => switch (key) {
  'cramps' => l10n.symptomCramps,
  'headache' => l10n.symptomHeadache,
  'tiredness' => l10n.symptomTiredness,
  'bloating' => l10n.symptomBloating,
  'mood_change' => l10n.symptomMoodChange,
  'back_pain' => l10n.symptomBackPain,
  _ => key,
};
