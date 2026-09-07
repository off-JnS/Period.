import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/presentation/app_shell.dart';
import 'package:period/presentation/providers.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/widgets.dart';

/// The two screens and the bar between them.
void main() {
  late AppDatabase db;

  setUp(() => db = aDatabase());

  Future<void> pumpShell(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const AppShell(),
      database: db,
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(FixedClock(aDate(2024, 5, 17))),
      ],
    );
  }

  Future<void> openCalendar(WidgetTester tester) async {
    await tester.tap(find.text('Calendar'));
    await settleDatabase(tester);
  }

  testWidgets('opens on Today', (tester) async {
    await pumpShell(tester);
    expect(find.text('Log today'), findsOneWidget);
    expect(find.text('May 2024'), findsNothing);
  });

  testWidgets('every destination is named', (tester) async {
    await pumpShell(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Today', 'Calendar', 'Settings']) {
      expect(find.text(label), findsWidgets, reason: 'missing $label');
    }
  });

  testWidgets('settings is one tap away', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Settings'));
    await settleDatabase(tester);
    expect(find.text('Your cycle right now'), findsOneWidget);
  });

  testWidgets('the calendar is one tap away', (tester) async {
    await pumpShell(tester);
    await openCalendar(tester);
    expect(find.text('May 2024'), findsOneWidget);
  });

  testWidgets('the calendar keeps its month while Today is visited', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCalendar(tester);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await settleDatabase(tester);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await settleDatabase(tester);
    expect(find.text('March 2024'), findsOneWidget);

    // Paging back three months and losing the place on a glance at Today would
    // make correcting an old entry tedious, which is the thing the calendar
    // exists to make easy.
    await tester.tap(find.text('Today').last);
    await settleDatabase(tester);
    await openCalendar(tester);
    expect(find.text('March 2024'), findsOneWidget);
  });

  testWidgets('German', (tester) async {
    await pumpWithDatabase(
      tester,
      const AppShell(),
      database: db,
      locale: const Locale('de'),
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(FixedClock(aDate(2024, 5, 17))),
      ],
    );
    expect(find.text('Heute'), findsWidgets);
    expect(find.text('Kalender'), findsWidgets);
    expect(find.text('Einstellungen'), findsWidgets);
  });
}
