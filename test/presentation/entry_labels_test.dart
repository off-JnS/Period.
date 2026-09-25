import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:period/l10n/app_localizations.dart';
import 'package:period/presentation/log/entry_labels.dart';

void main() {
  final keys = [
    ...offeredSymptomKeys,
    ...offeredMoodKeys,
    ...offeredDischargeKeys,
    ...offeredSexKeys,
    ...offeredOvulationTestKeys,
    pillTakenKey,
  ];

  for (final locale in AppLocalizations.supportedLocales) {
    test('every offered key has a ${locale.languageCode} label', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final key in keys) {
        final label = symptomLabel(l10n, key);
        expect(label, isNotNull, reason: key);
        expect(label, isNot(key), reason: 'raw key shown for $key');
      }
    });
  }

  test('an unknown key has no label rather than showing raw', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(symptomLabel(l10n, 'mood.someFutureMood'), isNull);
  });
}
