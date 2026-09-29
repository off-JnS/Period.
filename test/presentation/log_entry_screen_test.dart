import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/log/log_entry_screen.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// An option on the sheet by its name.
Finder option(String label) => find.widgetWithText(EntryOption, label);

/// Whether the tile around [finder] says it is chosen.
bool isSelected(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).flagsCollection.isSelected == Tristate.isTrue;

/// Scrolls to a folded section and opens it.
Future<void> openFold(WidgetTester tester, String heading) async {
  await tester.scrollUntilVisible(
    find.text(heading),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // To the top, so what opens underneath is on screen too.
  await Scrollable.ensureVisible(tester.element(find.text(heading)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(heading));
  await tester.pumpAndSettle();
}

void main() {
  final day = aDate(2024, 5, 17);

  /// Pumps the screen behind a button that pushes it, so the result it pops can
  /// be captured the way the real caller receives it.
  Future<LogEntryResult?> pumpAndClose(
    WidgetTester tester, {
    DayEntry? entry,
    bool isPeriodStart = false,
    bool offerPill = false,
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
                      offerPill: offerPill,
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
      for (final flow in ['None', 'Light', 'Medium', 'Heavy']) {
        expect(isSelected(tester, find.text(flow)), isFalse);
      }
    });
  });

  group('choosing', () {
    DayEntry entryOf(LogEntryResult? result) =>
        (result! as LogEntrySaved).draft.entry;

    testWidgets('a day of the week is one tap away', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.text('16'));
          await tester.pumpAndSettle();
          expect(find.text('Thursday, May 16'), findsOneWidget);
          await tester.tap(find.text('Save'));
        },
      );
      expect(entryOf(result).date, aDate(2024, 5, 16));
    });

    testWidgets('days still to come cannot be chosen', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.text('18'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(entryOf(result).date, day);
    });

    testWidgets('the arrows move a week at a time, never past today', (
      tester,
    ) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.bySemanticsLabel('Previous week'));
          await tester.pumpAndSettle();
          expect(find.text('Friday, May 10'), findsOneWidget);
          await tester.tap(find.bySemanticsLabel('Next week'));
          await tester.pumpAndSettle();
          expect(find.text('Today, May 17'), findsOneWidget);
          await tester.tap(find.text('Save'));
        },
      );
      expect(entryOf(result).date, day);
    });

    testWidgets('tapping the chosen flow again clears it', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.text('Light'));
          await tester.pumpAndSettle();
          expect(isSelected(tester, find.text('Light')), isTrue);
          await tester.tap(find.text('Light'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(entryOf(result).flow, isNull);
    });

    testWidgets('a folded section shows what is chosen in it', (tester) async {
      await pumpAndClose(
        tester,
        entry: aDayEntry(
          date: day,
          symptoms: {aSymptom(key: 'discharge.sticky')},
        ),
        act: (tester) async {
          await tester.scrollUntilVisible(
            find.text('Sticky'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          // Named beside the heading, with its options still folded away.
          expect(option('Creamy'), findsNothing);
          expect(find.text('Not recorded'), findsNWidgets(2));
        },
      );
    });
  });

  group('saving', () {
    testWidgets('returns what the user recorded', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await tester.tap(find.text('Medium'));
          await tester.pumpAndSettle();
          await tester.tap(option('Cramps'));
          await tester.pumpAndSettle();
          // The note is the last section and sits below the fold.
          await tester.scrollUntilVisible(
            find.byKey(noteFieldKey),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(find.byKey(noteFieldKey), 'slept badly');
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
            find.byKey(noteFieldKey),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(find.byKey(noteFieldKey), '   ');
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

      expect(isSelected(tester, find.text('Heavy')), isTrue);
      expect(tester.widget<EntryOption>(option('Headache')).selected, isTrue);
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

  group('mood, discharge, sex and the pill', () {
    Future<void> scrollTo(WidgetTester tester, Finder finder) =>
        tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );

    Set<String> keysOf(LogEntryResult? result) => {
      for (final symptom in (result! as LogEntrySaved).draft.entry.symptoms)
        symptom.key,
    };

    testWidgets('offers each as its own section', (tester) async {
      await pumpAndClose(tester, act: (tester) async {});
      for (final heading in ['Mood', 'Discharge', 'Sex']) {
        await scrollTo(tester, find.text(heading));
        expect(find.text(heading), findsOneWidget);
      }
    });

    testWidgets('any number of moods can be saved', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await scrollTo(tester, option('Sensitive'));
          await tester.tap(option('Calm'));
          await tester.tap(option('Sensitive'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(keysOf(result), {'mood.calm', 'mood.sensitive'});
    });

    testWidgets('discharge keeps only the latest choice', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await openFold(tester, 'Discharge');
          await tester.tap(option('Sticky'));
          await tester.pumpAndSettle();
          await tester.tap(option('Creamy'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(keysOf(result), {'discharge.creamy'});
    });

    testWidgets('tapping the chosen one again clears it', (tester) async {
      final result = await pumpAndClose(
        tester,
        entry: aDayEntry(
          date: day,
          symptoms: {aSymptom(key: 'sex.protected')},
        ),
        act: (tester) async {
          await openFold(tester, 'Sex');
          await tester.tap(option('Protected'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(keysOf(result), isEmpty);
    });

    testWidgets('choosing in one group leaves the others alone', (
      tester,
    ) async {
      final result = await pumpAndClose(
        tester,
        entry: aDayEntry(
          date: day,
          symptoms: {
            aSymptom(key: 'cramps'),
            aSymptom(key: 'mood.sad'),
          },
        ),
        act: (tester) async {
          await openFold(tester, 'Sex');
          await tester.tap(option('Unprotected'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(keysOf(result), {'cramps', 'mood.sad', 'sex.unprotected'});
    });

    testWidgets('sex says it is never combined with an estimate', (
      tester,
    ) async {
      await pumpAndClose(
        tester,
        act: (tester) async => openFold(tester, 'Sex'),
      );
      await scrollTo(tester, find.textContaining('never combined'));
      expect(find.textContaining('never combined with any estimate'), findsOne);
    });

    testWidgets('the pill switch appears only when offered', (tester) async {
      await pumpAndClose(tester, act: (tester) async {});
      expect(find.text('Pill taken'), findsNothing);
    });

    testWidgets('the pill can be logged when offered', (tester) async {
      final result = await pumpAndClose(
        tester,
        offerPill: true,
        act: (tester) async {
          await scrollTo(tester, find.text('Pill taken'));
          await tester.tap(find.text('Pill taken'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(keysOf(result), {'pill.taken'});
    });

    testWidgets('a pill logged earlier survives when not offered', (
      tester,
    ) async {
      final result = await pumpAndClose(
        tester,
        entry: aDayEntry(
          date: day,
          symptoms: {aSymptom(key: 'pill.taken')},
        ),
        act: (tester) async {
          await tester.tap(find.text('Light'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(keysOf(result), {'pill.taken'});
    });
  });

  group('body signals', () {
    Future<void> scrollTo(WidgetTester tester, Finder finder) =>
        tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );

    Finder temperatureField() => find.descendant(
      of: find.ancestor(
        of: find.text('Basal temperature'),
        matching: find.byType(Row),
      ),
      matching: find.byType(TextField),
    );

    testWidgets('a typed temperature is saved in hundredths', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await openFold(tester, 'Body signals');
          await tester.enterText(temperatureField(), '36,45');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(
        (result! as LogEntrySaved).draft.entry.temperatureCentiCelsius,
        3645,
      );
    });

    testWidgets('an implausible temperature is refused, not saved', (
      tester,
    ) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await openFold(tester, 'Body signals');
          await tester.enterText(temperatureField(), '3,65');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(find.textContaining('between 34 and 43'), findsOneWidget);
          // Fixing it clears the warning and lets it save.
          await tester.enterText(temperatureField(), '36,5');
          await tester.pumpAndSettle();
          expect(find.textContaining('between 34 and 43'), findsNothing);
          await tester.tap(find.text('Save'));
        },
      );
      expect(
        (result! as LogEntrySaved).draft.entry.temperatureCentiCelsius,
        3650,
      );
    });

    testWidgets('a stored temperature shows in the language format', (
      tester,
    ) async {
      await pumpAndClose(
        tester,
        locale: const Locale('de'),
        entry: aDayEntry(date: day).copyWith(temperatureCentiCelsius: 3645),
        act: (tester) async {
          // Shown beside the folded section's name, and in the field.
          await scrollTo(tester, find.text('36,45 °C'));
          await openFold(tester, 'Körpersignale');
          expect(find.text('36,45'), findsOneWidget);
        },
      );
    });

    testWidgets('an ovulation test result is saved', (tester) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await openFold(tester, 'Body signals');
          final chip = option('Positive').first;
          // scrollUntilVisible stops once any part shows; bring it fully in.
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(
        (result! as LogEntrySaved).draft.entry.symptoms.map((s) => s.key),
        ['ovulationTest.positive'],
      );
    });

    testWidgets('a pregnancy test result is saved, one at a time', (
      tester,
    ) async {
      final result = await pumpAndClose(
        tester,
        act: (tester) async {
          await openFold(tester, 'Body signals');
          final positive = option('Positive').last;
          final negative = option('Negative').last;
          await tester.ensureVisible(positive);
          await tester.pumpAndSettle();
          await tester.tap(negative);
          await tester.pumpAndSettle();
          await tester.tap(positive);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save'));
        },
      );
      expect(
        (result! as LogEntrySaved).draft.entry.symptoms.map((s) => s.key),
        ['pregnancyTest.positive'],
      );
    });

    testWidgets('says these are never used for any estimate', (tester) async {
      await pumpAndClose(
        tester,
        act: (tester) async {
          await openFold(tester, 'Body signals');
          await scrollTo(tester, find.textContaining('never uses these'));
          expect(find.textContaining('never uses these'), findsOneWidget);
        },
      );
    });
  });
}
