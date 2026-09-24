import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

void main() {
  final today = aDate(2024, 5, 17);

  CalendarViewData data({
    Set<CycleDate> periodStarts = const {},
    Set<CycleDate> loggedDays = const {},
    PredictedPeriod? predicted,
    int year = 2024,
    int month = 5,
  }) => CalendarViewData(
    year: year,
    month: month,
    today: today,
    periodStarts: periodStarts,
    loggedDays: loggedDays,
    predicted: predicted,
  );

  group('the month', () {
    testWidgets('shows every day of it', (tester) async {
      await pumpApp(tester, CalendarScreen(data: data()));

      // 1 and 31 both present; May has 31 days.
      expect(find.text('1'), findsWidgets);
      expect(find.text('31'), findsWidgets);
    });

    testWidgets('names itself in the reader locale', (tester) async {
      await pumpApp(tester, CalendarScreen(data: data()));
      expect(find.textContaining('May'), findsOneWidget);

      await pumpApp(
        tester,
        CalendarScreen(data: data()),
        locale: const Locale('de'),
      );
      expect(find.textContaining('Mai'), findsOneWidget);
    });

    testWidgets('steps backwards and forwards', (tester) async {
      var back = 0;
      var forward = 0;
      await pumpApp(
        tester,
        CalendarScreen(
          data: data(),
          onPreviousMonth: () => back++,
          onNextMonth: () => forward++,
        ),
      );

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(back, 1);
      expect(forward, 1);
    });
  });

  group('section 9: no state carried by colour alone', () {
    testWidgets('every marker is named in the legend', (tester) async {
      // The written half of the rule. Someone who cannot distinguish the tints
      // can still read what each shape means.
      await pumpApp(tester, CalendarScreen(data: data()));

      expect(find.text('Period start'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Estimated period'), findsOneWidget);
      expect(find.text('Logged'), findsOneWidget);
    });

    testWidgets('a period start says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        CalendarScreen(data: data(periodStarts: {aDate(2024, 5, 3)})),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'May 3, 2024.*Period start')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a logged day says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        CalendarScreen(data: data(loggedDays: {aDate(2024, 5, 8)})),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'May 8, 2024.*Logged')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an estimated day says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        CalendarScreen(
          data: data(
            predicted: PredictedPeriod(
              earliest: aDate(2024, 5, 20),
              latest: aDate(2024, 5, 24),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'May 21, 2024.*Estimated period')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('today says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, CalendarScreen(data: data()));

      expect(
        find.bySemanticsLabel(RegExp(r'May 17, 2024.*Today')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('logging from the grid', () {
    testWidgets('opens the day that was tapped', (tester) async {
      CycleDate? opened;
      await pumpApp(
        tester,
        CalendarScreen(data: data(), onSelectDay: (date) => opened = date),
      );

      // The 5th of the month, not a neighbouring month's 5th.
      await tester.tap(
        find
            .ancestor(of: find.text('5'), matching: find.byType(InkResponse))
            .first,
      );
      await tester.pumpAndSettle();

      expect(opened, aDate(2024, 5, 5));
    });

    testWidgets('refuses a day that has not happened yet', (tester) async {
      // A period cannot be observed in advance, and a future start date would
      // feed straight into the estimates.
      CycleDate? opened;
      await pumpApp(
        tester,
        CalendarScreen(data: data(), onSelectDay: (date) => opened = date),
      );

      // The 25th: unlike the 28th, it appears exactly once in this grid. A
      // Sunday-first May 2024 leads with 28, 29 and 30 April, and those are in
      // the past, so tapping "28" would legitimately open the April one.
      await tester.tap(
        find
            .ancestor(of: find.text('25'), matching: find.byType(InkResponse))
            .first,
      );
      await tester.pumpAndSettle();

      expect(opened, isNull);
    });

    testWidgets('still allows today itself', (tester) async {
      CycleDate? opened;
      await pumpApp(
        tester,
        CalendarScreen(data: data(), onSelectDay: (date) => opened = date),
      );

      await tester.tap(
        find
            .ancestor(of: find.text('17'), matching: find.byType(InkResponse))
            .first,
      );
      await tester.pumpAndSettle();

      expect(opened, today);
    });
  });

  group('layout', () {
    testWidgets('does not overflow at 160% text', (tester) async {
      await pumpApp(tester, CalendarScreen(data: data()), textScale: 1.6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a six-row month', (tester) async {
      await pumpApp(tester, CalendarScreen(data: data(year: 2024, month: 12)));
      expect(tester.takeException(), isNull);
      expect(find.text('31'), findsWidgets);
    });

    testWidgets('handles February in a leap year', (tester) async {
      await pumpApp(tester, CalendarScreen(data: data(year: 2024, month: 2)));
      expect(find.text('29'), findsWidgets);
    });
  });
}
