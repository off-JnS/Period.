import 'package:flutter/cupertino.dart';

import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';

/// The display name of [method].
String methodLabel(AppLocalizations l10n, ContraceptionMethod method) =>
    switch (method) {
      ContraceptionMethod.none => l10n.methodNone,
      ContraceptionMethod.condom => l10n.methodCondom,
      ContraceptionMethod.combinedPill => l10n.methodCombinedPill,
      ContraceptionMethod.progestinPill => l10n.methodProgestinPill,
      ContraceptionMethod.hormonalIud => l10n.methodHormonalIud,
      ContraceptionMethod.copperIud => l10n.methodCopperIud,
      ContraceptionMethod.implant => l10n.methodImplant,
      ContraceptionMethod.ring => l10n.methodRing,
      ContraceptionMethod.patch => l10n.methodPatch,
      ContraceptionMethod.injection => l10n.methodInjection,
      ContraceptionMethod.other => l10n.methodOther,
    };

/// The display name of [condition].
String conditionLabel(AppLocalizations l10n, KnownCondition condition) =>
    switch (condition) {
      KnownCondition.pcos => l10n.conditionPcos,
      KnownCondition.endometriosis => l10n.conditionEndometriosis,
      KnownCondition.adenomyosis => l10n.conditionAdenomyosis,
      KnownCondition.fibroids => l10n.conditionFibroids,
      KnownCondition.thyroid => l10n.conditionThyroid,
      KnownCondition.pmdd => l10n.conditionPmdd,
    };

/// The icon beside [method]: one per kind, so the list scans by shape.
IconData methodIcon(ContraceptionMethod method) => switch (method) {
  ContraceptionMethod.none => CupertinoIcons.minus_circle,
  ContraceptionMethod.condom => CupertinoIcons.shield,
  ContraceptionMethod.combinedPill ||
  ContraceptionMethod.progestinPill => CupertinoIcons.capsule,
  ContraceptionMethod.hormonalIud ||
  ContraceptionMethod.copperIud => CupertinoIcons.shield_lefthalf_fill,
  ContraceptionMethod.implant => CupertinoIcons.bandage,
  ContraceptionMethod.ring => CupertinoIcons.circle,
  ContraceptionMethod.patch => CupertinoIcons.square_on_square,
  ContraceptionMethod.injection => CupertinoIcons.eyedropper,
  ContraceptionMethod.other => CupertinoIcons.ellipsis_circle,
};

/// What the conditions row shows for [conditions].
String conditionsSummary(
  AppLocalizations l10n,
  Set<KnownCondition> conditions,
) => switch (conditions.length) {
  0 => l10n.notSet,
  1 => conditionLabel(l10n, conditions.single),
  final count => l10n.conditionsCount(count),
};
