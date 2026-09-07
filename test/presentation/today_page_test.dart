import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/clock.dart';
import 'package:period/presentation/providers.dart';
import 'package:period/presentation/today/today_page.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/widgets.dart';

/// The whole loop, against a real database.
///
/// Every other test in this project checks one layer. This one checks that they
/// are actually connected: tap the button, record a period start, and watch the
/// number on the screen change. Until this existed the app had three working
/// parts and no proof they were wired to each other.
void main() {
  late AppDatabase db;
  late FixedClock clock;

  setUp(() {
    db = aDatabase();
    clock = FixedClock(aDate(2024, 5, 17));
  });
  // No tearDown closing the database: pumpWithDatabase closes it in the right
  // order relative to unmounting the widget tree.

  Future<void> pumpToday(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const TodayPage(),
      database: db,
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
    );
  }

  Future<void> logPeriodStart(WidgetTester tester) async {
    await tester.tap(find.text('Log today'));
    await settleDatabase(tester);
    await tester.tap(find.byType(Switch));
    await settleDatabase(tester);
    await tester.tap(find.text('Save'));
    await settleDatabase(tester);
  }

  testWidgets('a fresh install asks for more data rather than guessing', (
    tester,
  ) async {
    await pumpToday(tester);
    expect(find.text('No cycle yet'), findsOneWidget);
    expect(
      find.textContaining('before an estimate is possible'),
      findsOneWidget,
    );
  });

  testWidgets('marking a period start makes the cycle day appear', (
    tester,
  ) async {
    await pumpToday(tester);
    expect(find.text('No cycle yet'), findsOneWidget);

    await logPeriodStart(tester);

    // The whole point: the write reached the database, the stream re-emitted,
    // and the derived value recomputed without anything being cached.
    expect(find.text('Day 1'), findsOneWidget);
  });

  testWidgets('the cycle day counts on from a start logged earlier', (
    tester,
  ) async {
    await db.logDao.addPeriodStart(aDate(2024, 5, 1));
    await pumpToday(tester);
    expect(find.text('Day 17'), findsOneWidget);
  });

  testWidgets('an estimate appears once there are enough cycles', (
    tester,
  ) async {
    for (final start in [
      aDate(2024, 3, 1),
      aDate(2024, 3, 29),
      aDate(2024, 4, 26),
    ]) {
      await db.logDao.addPeriodStart(start);
    }
    await pumpToday(tester);

    expect(find.text('Next period'), findsOneWidget);
    expect(find.text('Estimated, based on your entries'), findsOneWidget);
    expect(find.textContaining('before an estimate is possible'), findsNothing);
  });

  testWidgets('a new start changes the estimate immediately', (tester) async {
    // Section 4's whole design: nothing derived is stored, so the moment a
    // start is recorded every number on screen is recomputed from scratch.
    // 28 days apart, and today is 28 days after the second, so marking today
    // gives two consistent cycles rather than a wildly variable pair.
    for (final start in [aDate(2024, 3, 22), aDate(2024, 4, 19)]) {
      await db.logDao.addPeriodStart(start);
    }
    await pumpToday(tester);
    expect(
      find.textContaining('before an estimate is possible'),
      findsOneWidget,
      reason: 'one completed cycle is not enough to estimate from',
    );

    await logPeriodStart(tester);

    expect(find.text('Next period'), findsOneWidget);
    expect(find.text('Estimated, based on your entries'), findsOneWidget);
  });

  testWidgets('what was logged is there when the sheet reopens', (
    tester,
  ) async {
    await pumpToday(tester);

    await tester.tap(find.text('Log today'));
    await settleDatabase(tester);
    await tester.tap(find.text('Medium'));
    await tester.tap(find.text('Cramps'));
    await tester.enterText(find.byType(TextField), 'sore');
    await settleDatabase(tester);
    await tester.tap(find.text('Save'));
    await settleDatabase(tester);

    await tester.tap(find.text('Log today'));
    await settleDatabase(tester);

    expect(find.text('sore'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Medium'))
          .selected,
      isTrue,
    );
  });

  testWidgets('unmarking a period start removes the cycle again', (
    tester,
  ) async {
    await pumpToday(tester);
    await logPeriodStart(tester);
    expect(find.text('Day 1'), findsOneWidget);

    // Reopen and switch it back off.
    await tester.tap(find.text('Log today'));
    await settleDatabase(tester);
    await tester.tap(find.byType(Switch));
    await settleDatabase(tester);
    await tester.tap(find.text('Save'));
    await settleDatabase(tester);

    expect(find.text('No cycle yet'), findsOneWidget);
  });

  testWidgets('logging a day without marking it does not start a cycle', (
    tester,
  ) async {
    // Recording symptoms is not the same as saying a period began. Section 4
    // treats only an explicit mark as a cycle boundary.
    await pumpToday(tester);
    await tester.tap(find.text('Log today'));
    await settleDatabase(tester);
    await tester.tap(find.text('Cramps'));
    await settleDatabase(tester);
    await tester.tap(find.text('Save'));
    await settleDatabase(tester);

    expect(find.text('No cycle yet'), findsOneWidget);
    expect(await db.logDao.entryOn(aDate(2024, 5, 17)), isNotNull);
  });

  group('feedback after saving', () {
    testWidgets('confirms the save', (tester) async {
      // Section: interaction. The sheet closing is not, on its own, evidence
      // that anything was written.
      await pumpToday(tester);
      await logPeriodStart(tester);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('offers undo when a period start was removed', (tester) async {
      // Removing a start silently changes every estimate on the screen. It is
      // the one destructive thing this sheet can do, so it gets a way back.
      await pumpToday(tester);
      await logPeriodStart(tester);
      expect(find.text('Day 1'), findsOneWidget);

      await tester.tap(find.text('Log today'));
      await settleDatabase(tester);
      await tester.tap(find.byType(Switch));
      await settleDatabase(tester);
      await tester.tap(find.text('Save'));
      await settleDatabase(tester);

      expect(find.text('No cycle yet'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('undo restores the period start', (tester) async {
      await pumpToday(tester);
      await logPeriodStart(tester);

      await tester.tap(find.text('Log today'));
      await settleDatabase(tester);
      await tester.tap(find.byType(Switch));
      await settleDatabase(tester);
      await tester.tap(find.text('Save'));
      await settleDatabase(tester);
      expect(find.text('No cycle yet'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settleDatabase(tester);

      expect(find.text('Day 1'), findsOneWidget);
      expect(await db.logDao.allPeriodStarts(), hasLength(1));
    });

    testWidgets('offers no undo when nothing was removed', (tester) async {
      // Undo on an ordinary save would be noise, and would suggest something
      // destructive happened when it did not.
      await pumpToday(tester);
      await tester.tap(find.text('Log today'));
      await settleDatabase(tester);
      await tester.tap(find.text('Cramps'));
      await settleDatabase(tester);
      await tester.tap(find.text('Save'));
      await settleDatabase(tester);

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });
  });

  group('when the data cannot be opened', () {
    testWidgets('explains, and never shows the raw exception', (tester) async {
      // The likeliest real cause is a failed decrypt. A user seeing that needs
      // to know her entries are still on the device and that she can retry --
      // not a SqliteException. Section 8 also puts every visible string in the
      // ARB files, which a formatted error object can never be.
      await pumpWithDatabase(
        tester,
        const TodayPage(),
        database: db,
        overrides: [
          databaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          periodStartsProvider.overrideWith(
            (ref) =>
                throw StateError('SqliteException(26): file is not a database'),
          ),
        ],
      );

      expect(find.text('Period. could not open your data'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('SqliteException'), findsNothing);
      expect(find.textContaining('not a database'), findsNothing);
    });
  });

  test('the clock provider is the only source of today', () {
    // Section 3 allows one DateTime.now(); this keeps the UI honest about it.
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(aDate(2030, 1, 1))),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(clockProvider), isA<Clock>());
    expect(container.read(clockProvider).today(), aDate(2030, 1, 1));
  });
}
