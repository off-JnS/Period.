import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/log/log_entry_screen.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

void main() {
  final day = aDate(2024, 5, 17);

  /// Pumps the screen behind a button that pushes it, so the result it pops can
  /// be captured the way the real caller receives it.
  Future<LogEntryResult?> pumpAndClose(
    WidgetTester tester, {
    DayEntry? entry,
    bool isPeriodStart = false,
    Locale locale = const Locale('en'),
    required Future<void> Function(WidgetTester tester) act,
  }) async {
    LogEntryResult? result;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<LogEntryResult>(
                  MaterialPageRoute(
                    builder: (context) => LogEntryScreen(
                      date: day,
                      today: day,
                      entry: entry,
                      isPeriodStart: isPeriodStart,
                    ),
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
    await tester.pumpAndSettle();
    return result;
  }

  group('a day with nothing on it', () {
    testWidgets('offers every section', (tester) async {
      await pumpAndClose(tester, act: (tester) async {});

      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Period'), findsOneWidget);
      expect(find.text('Flow'), findsOneWidget);
      expect(find.text('Symptoms'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Note'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Note'), findsOneWidget);
    });

    testWidgets('does not offer to delete what was never logged', (
      tester,
    ) async {
      await pumpAndClose(tester, act: (tester) async {});
      expect(find.text('Delete entry'), findsNothing);
    });

    testWidgets('starts with flow not recorded rather than none', (
      tester,
    ) async {
      // "Not recorded" and "None" are different facts: one is silence, the
      // other is an observation that there was no bleeding. A fresh day must
      // not claim the second.
      await pumpAndClose(tester, act: (tester) async {});
      final notRecorded = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Not recorded'),
      );
      expect(notRecorded.selected, isTrue);
    });
  });

  group('saving', () {
    testWidgets('returns what the user recorded', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilterChip, 'Cramps'));
          await tester.pumpAndSettle();
          // The note is the last section and sits below the fold.
          await tester.scrollUntilVisible(
            find.byType(TextField),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(find.byType(TextField), 'slept badly');
          await tester.tap(find.text('Save'));
        },
      );

      expect(result, isA<LogEntrySaved>());
      final draft = (result! as LogEntrySaved).draft;
      expect(draft.entry.date, day);
      expect(draft.entry.flow, FlowIntensity.medium);
      expect(draft.entry.note, 'slept badly');
      expect(draft.entry.symptoms, contains(aSymptom(key: 'cramps')));
      expect(draft.isPeriodStart, isFalse);
    });

    testWidgets('records a period start when the switch is on', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );

      expect((result! as LogEntrySaved).draft.isPeriodStart, isTrue);
    });

    testWidgets('lets a period start be taken back off', (tester) async {
      // Users correct start dates constantly -- section 4 is built around it --
      // so unmarking has to be as reachable as marking.
      final result = await pumpAndClose(
        tester,
        isPeriodStart: true,
        entry: aDayEntry(date: day),
        act: (tester) async {
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );

      expect((result! as LogEntrySaved).draft.isPeriodStart, isFalse);
    });

    testWidgets('leaves an untouched note null rather than empty', (
      tester,
    ) async {
      // Section 5: a null means the user did not record it. An empty string
      // would claim she wrote an empty note.
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.text('Save'));
        },
      );

      expect((result! as LogEntrySaved).draft.entry.note, isNull);
    });

    testWidgets('treats a note of only spaces as no note', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          // The note is the last section and sits below the fold.
          await tester.scrollUntilVisible(
            find.byType(TextField),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(find.byType(TextField), '   ');
          await tester.tap(find.text('Save'));
        },
      );

      expect((result! as LogEntrySaved).draft.entry.note, isNull);
    });

    testWidgets('keeps a stored symptom this build cannot name', (
      tester,
    ) async {
      // A key retired from the chips, or one written by a newer build, has no
      // label here. It must survive a save untouched rather than being quietly
      // dropped from a day the user already logged.
      final result = await pumpAndClose(
        tester,
        entry: aDayEntry(
          date: day,
          symptoms: {aSymptom(key: 'somethingThisBuildHasNoNameFor')},
        ),
        act: (tester) async {
          await tester.tap(find.text('Save'));
        },
      );

      expect(
        (result! as LogEntrySaved).draft.entry.symptoms,
        contains(aSymptom(key: 'somethingThisBuildHasNoNameFor')),
      );
    });
  });

  group('an existing entry', () {
    testWidgets('opens with what was already recorded', (tester) async {
      await pumpAndClose(
        tester,
        entry: aDayEntry(
          date: day,
          flow: FlowIntensity.heavy,
          note: 'a note',
          symptoms: {aSymptom(key: 'headache')},
        ),
        act: (tester) async {},
      );

      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Heavy'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Headache'))
            .selected,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.text('a note'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('a note'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('asks before removing anything', (tester) async {
      await pumpAndClose(
        tester,
        entry: aDayEntry(date: day),
        act: (tester) async {
          await tester.scrollUntilVisible(
            find.text('Delete entry'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Delete entry'));
          await tester.pumpAndSettle();
          expect(find.text('Delete this entry?'), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        },
      );

      // Cancelling leaves the user on the entry, with nothing reported back.
      expect(find.text('Entry'), findsOneWidget);
    });

    testWidgets('reports the deletion once confirmed', (tester) async {
      final result = await pumpAndClose(
        tester,
        entry: aDayEntry(date: day),
        act: (tester) async {
          await tester.scrollUntilVisible(
            find.text('Delete entry'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Delete entry'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        },
      );

      expect(result, isA<LogEntryDeleted>());
      expect((result! as LogEntryDeleted).date, day);
    });

    testWidgets('offers deletion for a period start with no entry', (
      tester,
    ) async {
      // A day can be a period start and hold nothing else. There is still
      // something to remove.
      await pumpAndClose(tester, isPeriodStart: true, act: (tester) async {});
      await tester.scrollUntilVisible(
        find.text('Delete entry'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Delete entry'), findsOneWidget);
    });
  });

  group('German', () {
    testWidgets('renders without a hardcoded English string', (tester) async {
      await pumpAndClose(
        tester,
        locale: const Locale('de'),
        act: (tester) async {},
      );

      expect(find.text('Eintrag'), findsOneWidget);
      expect(find.text('Blutung'), findsOneWidget);
      expect(find.text('Symptome'), findsOneWidget);
      expect(find.text('Krämpfe'), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget);
    });
  });

  group('large text', () {
    testWidgets('does not overflow at 200%', (tester) async {
      // Section 9's accessibility floor: the layout grows rather than clipping.
      await pumpApp(
        tester,
        LogEntryScreen(date: day, today: day),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
