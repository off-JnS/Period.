import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/presentation/calendar/month_grid.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// The calendar as a pure widget, with no database behind it.
///
/// The spoken labels are checked as closely as the drawing, because CLAUDE.md
/// section 9 forbids meaning that rests on colour alone and a calendar is the
/// easiest place in the app to break that rule: forty-two circles that differ
/// only in shade say nothing to a screen reader and nothing to a user who
/// cannot tell them apart.
void main() {
  // April 2024 begins on a Monday, so a Monday-first grid has no leading
  // padding and five clean weeks -- the days in it are easy to reason about.
  final april = MonthGrid.of(aDate(2024, 4, 1), firstWeekday: 1);
  final today = aDate(2024, 4, 15);

  CalendarViewData data({
    CycleDate? now,
    Set<CycleDate> periodStarts = const {},
    Set<CycleDate> loggedDays = const {},
    PredictedPeriod? prediction,
  }) => CalendarViewData(
    today: now ?? today,
    periodStarts: periodStarts,
    loggedDays: loggedDays,
    prediction: prediction,
  );

  final busyMonth = data(
    periodStarts: {aDate(2024, 4, 3)},
    loggedDays: {aDate(2024, 4, 3), aDate(2024, 4, 4), aDate(2024, 4, 5)},
    // Runs off the end of the month and into the padding days, which is where a
    // window that straddles a month boundary would otherwise vanish.
    prediction: PredictedPeriod(
      earliest: aDate(2024, 4, 29),
      latest: aDate(2024, 5, 3),
    ),
  );

  // No ensureSemantics: testWidgets enables semantics by default, and a handle
  // taken here would outlive the framework's own end-of-test check.
  Future<void> pumpCalendar(
    WidgetTester tester, {
    CalendarViewData? view,
    MonthGrid? grid,
    void Function(CycleDate)? onSelectDay,
    VoidCallback? onPreviousMonth,
    VoidCallback? onNextMonth,
    Locale locale = const Locale('en'),
  }) async {
    await pumpApp(
      tester,
      CalendarScreen(
        data: view ?? busyMonth,
        grid: grid ?? april,
        onSelectDay: onSelectDay ?? (_) {},
        onPreviousMonth: onPreviousMonth,
        onNextMonth: onNextMonth,
      ),
      locale: locale,
    );
  }

  group('every state is said in words, not only drawn', () {
    testWidgets('a period start', (tester) async {
      await pumpCalendar(tester);
      expect(
        find.bySemanticsLabel('April 3, 2024, Period start'),
        findsOneWidget,
      );
    });

    testWidgets('a logged day', (tester) async {
      await pumpCalendar(tester);
      expect(find.bySemanticsLabel('April 4, 2024, Logged'), findsOneWidget);
    });

    testWidgets('today', (tester) async {
      await pumpCalendar(tester);
      expect(find.bySemanticsLabel('April 15, 2024, Today'), findsOneWidget);
    });

    testWidgets('an estimated day', (tester) async {
      await pumpCalendar(tester);
      expect(
        find.bySemanticsLabel('April 29, 2024, Estimated period'),
        findsOneWidget,
      );
    });

    testWidgets('a day with nothing on it says only its date', (tester) async {
      await pumpCalendar(tester);
      expect(find.bySemanticsLabel('April 10, 2024'), findsOneWidget);
    });

    testWidgets('a day that is several things at once says all of them', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        view: data(
          periodStarts: {today},
          loggedDays: {today},
          prediction: PredictedPeriod(earliest: today, latest: today),
        ),
      );
      // "Logged" is left out: a period start is by definition a logged day, and
      // saying both would pad the label without adding anything.
      expect(
        find.bySemanticsLabel(
          'April 15, 2024, Today, Period start, '
          'Estimated period',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the legend names every marker it draws', (tester) async {
      await pumpCalendar(tester);
      for (final label in ['Period start', 'Logged', 'Estimated period']) {
        expect(find.widgetWithText(Row, label), findsWidgets);
      }
    });
  });

  group('logging a day', () {
    testWidgets('reports the day that was tapped', (tester) async {
      CycleDate? selected;
      await pumpCalendar(tester, onSelectDay: (day) => selected = day);

      await tester.tap(find.bySemanticsLabel('April 10, 2024'));
      expect(selected, aDate(2024, 4, 10));
    });

    testWidgets('a padding day from the next month is still a real day', (
      tester,
    ) async {
      CycleDate? selected;
      // Looking back at April from May, so the padding days at the foot of the
      // grid are in the past and therefore loggable.
      await pumpCalendar(
        tester,
        view: data(now: aDate(2024, 5, 20)),
        onSelectDay: (day) => selected = day,
      );

      // May 1 is drawn faintly because it is not this month, but refusing to
      // log it would be arbitrary: it is a day like any other.
      await tester.tap(find.bySemanticsLabel('May 1, 2024'));
      expect(selected, aDate(2024, 5, 1));
    });

    testWidgets('a future day cannot be logged', (tester) async {
      CycleDate? selected;
      await pumpCalendar(tester, onSelectDay: (day) => selected = day);

      // Drawn, because the estimate lives in the future and is the reason to
      // look ahead. Not writable, because a period start dated forward would
      // invent a cycle and move every estimate on the strength of a plan.
      await tester.tap(
        find.bySemanticsLabel('April 29, 2024, Estimated period'),
      );
      expect(selected, isNull);
    });

    testWidgets('tomorrow is already too far ahead', (tester) async {
      CycleDate? selected;
      await pumpCalendar(tester, onSelectDay: (day) => selected = day);

      await tester.tap(find.bySemanticsLabel('April 16, 2024'));
      expect(selected, isNull);
    });

    testWidgets('today itself can still be logged', (tester) async {
      CycleDate? selected;
      await pumpCalendar(tester, onSelectDay: (day) => selected = day);

      await tester.tap(find.bySemanticsLabel('April 15, 2024, Today'));
      expect(selected, today);
    });
  });

  group('an empty month', () {
    testWidgets('says so rather than showing a blank grid', (tester) async {
      await pumpCalendar(tester, view: data());
      expect(find.text('Nothing logged this month'), findsOneWidget);
    });

    testWidgets('stays quiet once anything is logged', (tester) async {
      await pumpCalendar(tester);
      expect(find.text('Nothing logged this month'), findsNothing);
    });

    testWidgets('a logged day in the padding does not count as this month', (
      tester,
    ) async {
      await pumpCalendar(tester, view: data(loggedDays: {aDate(2024, 5, 2)}));
      expect(find.text('Nothing logged this month'), findsOneWidget);
    });
  });

  group('moving between months', () {
    testWidgets('the header names the month and year', (tester) async {
      await pumpCalendar(tester);
      expect(find.text('April 2024'), findsOneWidget);
    });

    testWidgets('the arrows are labelled for a screen reader', (tester) async {
      // Two icons with no text beside them. Without a label they are announced
      // as an unnamed button, which is the whole of what a user hears.
      await pumpCalendar(tester, onPreviousMonth: () {}, onNextMonth: () {});
      expect(find.bySemanticsLabel('Previous month'), findsOneWidget);
      expect(find.bySemanticsLabel('Next month'), findsOneWidget);
    });

    testWidgets('the arrows call back', (tester) async {
      var back = 0;
      var forward = 0;
      await pumpCalendar(
        tester,
        onPreviousMonth: () => back++,
        onNextMonth: () => forward++,
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(back, 1);
      expect(forward, 1);
    });
  });

  group('the week starts where the reader expects', () {
    testWidgets('Monday first', (tester) async {
      await pumpCalendar(tester);
      final headings = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ExcludeSemantics),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toList();
      expect(headings.first, 'Mon');
      expect(headings.last, 'Sun');
    });

    testWidgets('Sunday first', (tester) async {
      await pumpCalendar(
        tester,
        grid: MonthGrid.of(aDate(2024, 4, 1), firstWeekday: 7),
      );
      final headings = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ExcludeSemantics),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toList();
      expect(headings.first, 'Sun');
      expect(headings.last, 'Sat');
    });

    testWidgets('the headings cannot disagree with the days beneath them', (
      tester,
    ) async {
      // The grid carries its own first weekday, so the heading row and the day
      // rows are computed from the same number rather than from two callers
      // that have to remember to agree. April 1 2024 was a Monday.
      final sundayFirst = MonthGrid.of(aDate(2024, 4, 1), firstWeekday: 7);
      expect(sundayFirst.firstWeekday, 7);
      expect(sundayFirst.days.first, aDate(2024, 3, 31));

      await pumpCalendar(tester, grid: sundayFirst);
      expect(find.bySemanticsLabel('March 31, 2024'), findsOneWidget);
    });
  });

  testWidgets('German', (tester) async {
    await pumpCalendar(tester, locale: const Locale('de'));
    expect(find.text('April 2024'), findsOneWidget);
    expect(
      find.bySemanticsLabel('3. April 2024, Periodenbeginn'),
      findsWidgets,
    );
  });

  group('the month keeps its year at any text size', () {
    // The month moved into the app bar, between two icon buttons, which is a
    // far tighter box than the full-width row it replaced. On a 320px phone at
    // 200% text "September 2024" wants 216px and is given 184, so without a
    // second line the year is what gets dropped -- and the year is the half
    // that matters when paging across January.
    //
    // Checked rather than clamped: the comment on the day grid promises that
    // everything outside it, the month included, still scales all the way.
    for (final month in [9, 11, 12]) {
      for (final width in [320.0, 400.0]) {
        testWidgets('month $month at 200% on ${width.toInt()}px', (
          tester,
        ) async {
          final day = aDate(2024, month, 15);
          await pumpApp(
            tester,
            CalendarScreen(
              data: data(now: day),
              grid: MonthGrid.of(day, firstWeekday: 1),
              onSelectDay: (_) {},
            ),
            locale: const Locale('de'),
            textScale: 2,
            surface: Size(width, 900),
          );

          final title = find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(Text),
          );
          final paragraph = tester.renderObject<RenderParagraph>(title.first);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason:
                'the month title is truncated at 200% text on '
                '${width.toInt()}px',
          );

          // Both halves are needed and only this catches the second. Letting
          // the text take a second line without growing the bar to hold it
          // puts the title at -9..65 inside a 0..56 bar: it spills out of both
          // ends and is clipped, and nothing throws. A test that only asked
          // whether the paragraph was truncated passed that happily.
          final bar = tester.getRect(find.byType(AppBar));
          final rect = tester.getRect(title.first);
          expect(
            rect.top >= bar.top && rect.bottom <= bar.bottom,
            isTrue,
            reason:
                'the month title is drawn outside the app bar at 200% text on '
                '${width.toInt()}px: title $rect, bar $bar',
          );
        });
      }
    }
  });
}
