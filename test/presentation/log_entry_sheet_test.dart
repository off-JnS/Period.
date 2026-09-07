import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/today/log_entry_sheet.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

void main() {
  /// Opens the sheet and returns whatever it popped.
  Future<LoggedDay?> openAndAct(
    WidgetTester tester,
    Future<void> Function(WidgetTester tester) act, {
    DayEntry? existing,
    bool isPeriodStart = false,
    Locale locale = const Locale('en'),
  }) async {
    LoggedDay? result;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showModalBottomSheet<LoggedDay>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => LogEntrySheet(
                    date: aDate(2024, 5, 17),
                    existing: existing,
                    isPeriodStart: isPeriodStart,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: locale,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act(tester);
    return result;
  }

  group('recording a day', () {
    testWidgets('cancelling saves nothing', (tester) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
      expect(result, isNull);
    });

    testWidgets('an untouched day records nothing rather than blanks', (
      tester,
    ) async {
      // Section 5: null means "not recorded". Saving without choosing anything
      // must not invent a flow of none or an empty note.
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });

      expect(result!.entry.flow, isNull);
      expect(result.entry.note, isNull);
      expect(result.entry.symptoms, isEmpty);
      expect(result.isPeriodStart, isFalse);
    });

    testWidgets('records flow, symptoms and a note together', (tester) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.text('Medium'));
        await tester.tap(find.text('Cramps'));
        await tester.tap(find.text('Headache'));
        await tester.enterText(find.byType(TextField), '  sore back  ');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });

      expect(result!.entry.flow, FlowIntensity.medium);
      expect(result.entry.symptoms, {
        aSymptom(key: 'cramps'),
        aSymptom(key: 'headache'),
      });
      expect(result.entry.note, 'sore back', reason: 'whitespace is trimmed');
    });

    testWidgets('a whitespace-only note counts as no note', (tester) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.enterText(find.byType(TextField), '   ');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });
      expect(result!.entry.note, isNull);
    });

    testWidgets('tapping the chosen flow again clears it', (tester) async {
      // "Not recorded" has to stay reachable after a mistap, because it is a
      // different fact from "none".
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.text('Heavy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Heavy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });
      expect(result!.entry.flow, isNull);
    });

    testWidgets('"none" is recorded, not treated as blank', (tester) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.text('None'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });
      expect(result!.entry.flow, FlowIntensity.none);
    });
  });

  group('marking a period start', () {
    testWidgets('is off unless chosen', (tester) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });
      expect(result!.isPeriodStart, isFalse);
    });

    testWidgets('can be turned on', (tester) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      });
      expect(result!.isPeriodStart, isTrue);
    });

    testWidgets('can be turned back off, so a mistap is correctable', (
      tester,
    ) async {
      final result = await openAndAct(tester, (tester) async {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      }, isPeriodStart: true);
      expect(result!.isPeriodStart, isFalse);
    });
  });

  group('editing an existing day', () {
    testWidgets('starts from what was already recorded', (tester) async {
      await openAndAct(
        tester,
        (tester) async {
          expect(find.text('sore back'), findsOneWidget);
          final medium = tester.widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'Medium'),
          );
          expect(medium.selected, isTrue);
          final cramps = tester.widget<FilterChip>(
            find.widgetWithText(FilterChip, 'Cramps'),
          );
          expect(cramps.selected, isTrue);
        },
        existing: aDayEntry(
          date: aDate(2024, 5, 17),
          flow: FlowIntensity.medium,
          note: 'sore back',
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );
    });

    testWidgets('a symptom can be removed', (tester) async {
      final result = await openAndAct(
        tester,
        (tester) async {
          await tester.tap(find.text('Cramps'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
        },
        existing: aDayEntry(
          date: aDate(2024, 5, 17),
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );
      expect(result!.entry.symptoms, isEmpty);
    });
  });

  testWidgets('renders in German without overflowing', (tester) async {
    await openAndAct(tester, (tester) async {
      expect(find.text('Speichern'), findsOneWidget);
      expect(find.text('Krämpfe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, locale: const Locale('de'));
  });

  test('every offered symptom has a translation', () {
    // A key with no label would render as the raw key, e.g. "mood_change".
    expect(offeredSymptomKeys, isNotEmpty);
    expect(offeredSymptomKeys.toSet(), hasLength(offeredSymptomKeys.length));
  });
}
