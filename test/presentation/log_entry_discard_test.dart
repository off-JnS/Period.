import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/log/log_entry_screen.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// Leaving the log sheet must never lose what she entered without asking.
void main() {
  final day = aDate(2024, 5, 17);

  /// Opens the real sheet, as the app does, and records how it closed.
  Future<List<Object?>> openSheet(
    WidgetTester tester, {
    DayEntry? entry,
  }) async {
    final results = <Object?>[];
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(
                await showLogEntrySheet(
                  context,
                  LogEntryScreen(date: day, today: day, entry: entry),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  bool sheetOpen() => find.byType(LogEntryScreen).evaluate().isNotEmpty;

  testWidgets('Cancel with nothing changed closes without asking', (
    tester,
  ) async {
    final results = await openSheet(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsNothing);
    expect(sheetOpen(), isFalse);
    expect(results, [null]);
  });

  testWidgets('Cancel after a change asks first', (tester) async {
    await openSheet(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsOneWidget);
    expect(sheetOpen(), isTrue);
  });

  testWidgets('Keep editing returns to the form with the change intact', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(sheetOpen(), isTrue);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Heavy'))
          .selected,
      isTrue,
    );
  });

  testWidgets('Discard closes and reports nothing', (tester) async {
    final results = await openSheet(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();

    expect(sheetOpen(), isFalse);
    expect(results, [null]);
  });

  testWidgets('a change undone again is not a change', (tester) async {
    await openSheet(
      tester,
      entry: aDayEntry(date: day, flow: FlowIntensity.light),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Light'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsNothing);
    expect(sheetOpen(), isFalse);
  });

  testWidgets('typing a note counts as a change', (tester) async {
    await openSheet(tester);
    await tester.scrollUntilVisible(
      find.byKey(noteFieldKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(noteFieldKey), 'tired');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsOneWidget);
  });

  testWidgets('Save is never held up by the prompt', (tester) async {
    final results = await openSheet(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsNothing);
    expect(results.single, isA<LogEntrySaved>());
  });

  group('swiping the sheet down', () {
    Future<void> swipeDown(WidgetTester tester) async {
      await tester.fling(find.text('Entry'), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();
    }

    testWidgets('dismisses it when nothing was changed', (tester) async {
      await openSheet(tester);
      await swipeDown(tester);
      expect(sheetOpen(), isFalse);
    });

    testWidgets('does nothing once something was changed', (tester) async {
      await openSheet(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pumpAndSettle();

      await swipeDown(tester);
      expect(sheetOpen(), isTrue);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Heavy'))
            .selected,
        isTrue,
      );
    });
  });
}
