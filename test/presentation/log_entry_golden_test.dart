import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/log/log_entry_screen.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// Golden tests for the log sheet, tall enough to show every section.
/// Regenerate deliberately: `flutter test --update-goldens`.
void main() {
  final day = aDate(2024, 5, 17);

  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    bool offerPill = false,
  }) async {
    await pumpApp(
      tester,
      LogEntryScreen(
        date: day,
        today: day,
        offerPill: offerPill,
        entry: aDayEntry(
          date: day,
          flow: FlowIntensity.light,
          symptoms: {
            aSymptom(key: 'cramps'),
            aSymptom(key: 'mood.calm'),
            aSymptom(key: 'discharge.sticky'),
            aSymptom(key: 'sex.none'),
            aSymptom(key: 'pill.taken'),
            aSymptom(key: 'ovulationTest.negative'),
          },
        ).copyWith(temperatureCentiCelsius: 3645),
      ),
      locale: locale,
      brightness: brightness,
      surface: const Size(400, 2500),
    );
    await expectLater(
      find.byType(LogEntryScreen),
      matchesGoldenFile('goldens/log_$name.png'),
    );
  }

  testWidgets('every section', (tester) => expectGolden(tester, 'all'));

  testWidgets(
    'German, on hormonal contraception',
    (tester) => expectGolden(
      tester,
      'german_pill',
      locale: const Locale('de'),
      offerPill: true,
    ),
  );

  testWidgets(
    'dark',
    (tester) => expectGolden(tester, 'dark', brightness: Brightness.dark),
  );
}
