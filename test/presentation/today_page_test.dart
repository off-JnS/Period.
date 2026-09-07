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
