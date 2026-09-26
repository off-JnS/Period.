import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/fertile_window.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

void main() {
  final today = aDate(2024, 5, 17);

  CalendarViewData data({
    CycleDate? on,
    Set<CycleDate> periodStarts = const {},
    Map<CycleDate, FlowIntensity> flowByDay = const {},
    Set<CycleDate> loggedDays = const {},
    PredictedPeriod? predicted,
    FertileWindowEstimate? fertileWindow,
  }) => CalendarViewData(
    today: on ?? today,
    periodStarts: periodStarts,
    flowByDay: flowByDay,
    loggedDays: loggedDays,
    predicted: predicted,
    fertileWindow: fertileWindow,
  );

  Future<void> pump(
    WidgetTester tester,
    CalendarViewData data, {
    void Function(CycleDate)? onSelectDay,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) => pumpApp(
    tester,
    CalendarScreen(data: data, onSelectDay: onSelectDay),
    locale: locale,
    textScale: textScale,
  );

  Finder day(String pattern) => find.bySemanticsLabel(RegExp(pattern));

  group('the scroll', () {
    testWidgets('opens on the current month, with every day of it', (
      tester,
    ) async {
      await pump(tester, data());
      expect(find.text('May'), findsOneWidget);
      for (var d = 1; d <= 31; d++) {
        expect(day('^May $d, 2024'), findsOneWidget, reason: 'May $d');
      }
    });

    testWidgets('leaves out the neighbouring months\' days in each grid', (
      tester,
    ) async {
      await pump(tester, data());
      // May 2024 starts on a Wednesday: the grid would otherwise show the
      // end of April on its first row.
      expect(day('^April 30, 2024'), findsNothing);
    });

    testWidgets('names months of other years with their year', (
      tester,
    ) async {
      await pump(tester, data());
      await tester.scrollUntilVisible(
        find.text('December 2023'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('December 2023'), findsOneWidget);
    });

    testWidgets('keeps going forward, past the end of the year', (
      tester,
    ) async {
      await pump(tester, data());
      await tester.scrollUntilVisible(
        find.text('February 2025'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('February 2025'), findsOneWidget);
    });

    testWidgets('reaches years back without building every month between', (
      tester,
    ) async {
      await pump(tester, data());
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 20000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('20'), findsWidgets);
    });

    testWidgets('names months in the reader locale', (tester) async {
      await pump(tester, data(), locale: const Locale('de'));
      expect(find.text('Mai'), findsOneWidget);
      expect(find.text('Heute'), findsOneWidget);
    });
  });

  group('what a day shows', () {
    testWidgets('a period start says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, data(periodStarts: {aDate(2024, 5, 3)}));
      expect(day(r'^May 3, 2024.*Period start'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('every day with flow is a period day; none is not', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        data(
          periodStarts: {aDate(2024, 5, 3)},
          flowByDay: {
            aDate(2024, 5, 3): FlowIntensity.heavy,
            aDate(2024, 5, 4): FlowIntensity.light,
            aDate(2024, 5, 5): FlowIntensity.none,
          },
          loggedDays: {aDate(2024, 5, 3), aDate(2024, 5, 4), aDate(2024, 5, 5)},
        ),
      );
      expect(day(r'^May 4, 2024.*Period'), findsOneWidget);
      expect(day(r'^May 5, 2024, Logged$'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a logged day says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, data(loggedDays: {aDate(2024, 5, 9)}));
      expect(day(r'^May 9, 2024.*Logged'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an estimated day says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        data(
          predicted: PredictedPeriod(
            earliest: aDate(2024, 5, 26),
            latest: aDate(2024, 5, 30),
          ),
        ),
      );
      expect(day(r'^May 28, 2024.*Estimated period'), findsOneWidget);
      expect(day(r'^May 25, 2024.*Estimated period'), findsNothing);
      handle.dispose();
    });

    testWidgets('today says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, data());
      expect(day(r'^May 17, 2024, Today'), findsOneWidget);
      handle.dispose();
    });
  });

  group('text', () {
    testWidgets('a month says nothing beyond its name', (tester) async {
      await pump(
        tester,
        data(
          periodStarts: {aDate(2024, 5, 3)},
          flowByDay: {
            for (var d = 3; d <= 7; d++) aDate(2024, 5, d): FlowIntensity.medium,
          },
          predicted: PredictedPeriod(
            earliest: aDate(2024, 5, 29),
            latest: aDate(2024, 6, 2),
          ),
        ),
      );
      expect(find.textContaining('Period'), findsNothing);
      expect(find.textContaining('estimated'), findsNothing);
    });

    testWidgets('except the fertile window caveat, wherever it is drawn', (
      tester,
    ) async {
      await pump(
        tester,
        data(
          fertileWindow: FertileWindowEstimate(
            earliest: aDate(2024, 5, 10),
            latest: aDate(2024, 5, 19),
          ),
        ),
      );
      expect(
        find.textContaining('Not suitable for preventing pregnancy'),
        findsOneWidget,
      );
    });
  });

  group('the legend', () {
    testWidgets('names every marker in words', (tester) async {
      await pump(tester, data());
      await tester.tap(find.byIcon(CupertinoIcons.info_circle));
      await tester.pumpAndSettle();
      for (final label in [
        'What the marks mean',
        'Period',
        'Estimated period',
        'Today',
        'Logged',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Estimated fertile window'), findsNothing);
    });

    testWidgets('names the fertile window, with its caveat, when it shows', (
      tester,
    ) async {
      await pump(
        tester,
        data(
          fertileWindow: FertileWindowEstimate(
            earliest: aDate(2024, 5, 10),
            latest: aDate(2024, 5, 19),
          ),
        ),
      );
      await tester.tap(find.byIcon(CupertinoIcons.info_circle));
      await tester.pumpAndSettle();
      expect(find.text('Estimated fertile window'), findsOneWidget);
      expect(
        find.textContaining('Not suitable for preventing pregnancy'),
        findsWidgets,
      );
    });
  });

  group('tapping', () {
    testWidgets('opens the day that was tapped', (tester) async {
      final handle = tester.ensureSemantics();
      final opened = <CycleDate>[];
      await pump(tester, data(), onSelectDay: opened.add);
      await tester.tap(day(r'^May 6, 2024'));
      expect(opened, [aDate(2024, 5, 6)]);
      handle.dispose();
    });

    testWidgets('opens a future day too, which says it has not happened', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final opened = <CycleDate>[];
      await pump(tester, data(), onSelectDay: opened.add);
      await tester.tap(day(r'^May 20, 2024'));
      expect(opened, [aDate(2024, 5, 20)]);
      expect(day(r'^May 20, 2024.*Not yet'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('still allows today itself', (tester) async {
      final handle = tester.ensureSemantics();
      final opened = <CycleDate>[];
      await pump(tester, data(), onSelectDay: opened.add);
      await tester.tap(day(r'^May 17, 2024'));
      expect(opened, [today]);
      handle.dispose();
    });
  });

  group('layout', () {
    testWidgets('does not overflow at 160% text', (tester) async {
      await pump(tester, data(), textScale: 1.6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles February in a leap year', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, data(on: aDate(2024, 2, 10)));
      expect(day(r'^February 29, 2024'), findsOneWidget);
      handle.dispose();
    });
  });
}
