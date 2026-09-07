import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/today/log_entry_sheet.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// Pictures of the logging sheet, so a change to what a person sees shows up as
/// an image diff. Regenerate deliberately with `flutter test --update-goldens`
/// and read the diff before accepting it.
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    DayEntry? existing,
    bool isPeriodStart = false,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      Scaffold(
        body: LogEntrySheet(
          date: aDate(2024, 5, 17),
          existing: existing,
          isPeriodStart: isPeriodStart,
        ),
      ),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
    );
    await expectLater(
      find.byType(LogEntrySheet),
      matchesGoldenFile('goldens/log_$name.png'),
    );
  }

  testWidgets('an empty day', (tester) async {
    await expectGolden(tester, 'empty');
  });

  testWidgets('a day with everything recorded', (tester) async {
    await expectGolden(
      tester,
      'filled',
      isPeriodStart: true,
      existing: aDayEntry(
        date: aDate(2024, 5, 17),
        flow: FlowIntensity.medium,
        note: 'Slept badly, sore back all afternoon.',
        symptoms: {
          aSymptom(key: 'cramps'),
          aSymptom(key: 'tiredness'),
          aSymptom(key: 'back_pain'),
        },
      ),
    );
  });

  testWidgets('dark mode', (tester) async {
    await expectGolden(
      tester,
      'dark',
      brightness: Brightness.dark,
      existing: aDayEntry(
        date: aDate(2024, 5, 17),
        flow: FlowIntensity.heavy,
        symptoms: {aSymptom(key: 'headache')},
      ),
    );
  });

  testWidgets('German, which runs about a third longer', (tester) async {
    await expectGolden(
      tester,
      'german',
      locale: const Locale('de'),
      isPeriodStart: true,
      existing: aDayEntry(
        date: aDate(2024, 5, 17),
        flow: FlowIntensity.light,
        symptoms: {aSymptom(key: 'mood_change')},
      ),
    );
  });
}
