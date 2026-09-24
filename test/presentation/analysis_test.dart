import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/analysis/analysis_page.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// Section 7's awkward-case list applies to this screen almost line for line,
/// so the derivation is tested as a function first and the rendering second.
void main() {
  group('analysisFrom', () {
    test('no cycles at all', () {
      final data = analysisFrom([]);
      expect(data.cycles, isEmpty);
      expect(data.medianLength, isNull);
      expect(data.shortest, isNull);
    });

    test('one start is one cycle, in progress, with no statistics', () {
      // A single start has no second start to measure against, so there is no
      // length yet -- not a length of zero.
      final data = analysisFrom([aDate(2024, 1, 1)]);
      expect(data.cycles, hasLength(1));
      expect(data.cycles.single.isInProgress, isTrue);
      expect(data.eligible, isEmpty);
      expect(data.medianLength, isNull);
    });

    test('two starts give one completed cycle, still too few to summarise', () {
      final data = analysisFrom([aDate(2024, 1, 1), aDate(2024, 1, 29)]);
      expect(data.eligible, hasLength(1));
      // One cycle is a fact, not a usual length. Section 8's honesty applies to
      // an average as much as to an estimate.
      expect(data.medianLength, isNull);
    });

    test('three starts give a usual length', () {
      final data = analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 3),
      );
      expect(data.eligible, hasLength(2));
      expect(data.medianLength, 28);
      expect(data.shortest, 28);
      expect(data.longest, 28);
    });

    test('a 21-day and a 40-day cycle are both kept', () {
      // Both are real human cycles. Dropping either would make the app quietly
      // wrong about the person it belongs to.
      final data = analysisFrom([
        aDate(2024, 1, 1),
        aDate(2024, 1, 22), // 21 days
        aDate(2024, 3, 2), // 40 days
        aDate(2024, 3, 30),
      ]);
      expect(data.eligible, hasLength(3));
      expect(data.shortest, 21);
      expect(data.longest, 40);
    });

    test('a three-month gap is excluded as a logging artifact', () {
      // Over 90 days is a missed start merging two cycles, not a real one.
      final data = analysisFrom([
        aDate(2024, 1, 1),
        aDate(2024, 1, 29),
        aDate(2024, 6, 1),
        aDate(2024, 6, 29),
      ]);
      expect(data.eligible.every((cycle) => cycle.lengthInDays! <= 90), isTrue);
      expect(data.longest, lessThanOrEqualTo(90));
    });

    test('starts logged out of order are sorted', () {
      final jumbled = analysisFrom([
        aDate(2024, 3, 1),
        aDate(2024, 1, 1),
        aDate(2024, 2, 1),
      ]);
      expect(jumbled.cycles.first.start, aDate(2024, 1, 1));
      expect(jumbled.cycles.last.start, aDate(2024, 3, 1));
    });

    test('the same day logged twice counts once', () {
      final data = analysisFrom([
        aDate(2024, 1, 1),
        aDate(2024, 1, 1),
        aDate(2024, 1, 29),
      ]);
      expect(data.cycles, hasLength(2));
    });

    test('only the most recent cycles feed the statistics', () {
      final data = analysisFrom(
        regularPeriodStarts(from: aDate(2023, 1, 2), length: 28, count: 12),
      );
      // statisticsWindow is 6.
      expect(data.eligible, hasLength(6));
    });
  });

  group('the screen', () {
    testWidgets('says what to do when there is no history', (tester) async {
      await pumpApp(tester, AnalysisScreen(data: analysisFrom([])));
      expect(
        find.text('Log a period to start building your history'),
        findsOneWidget,
      );
    });

    testWidgets('explains why there is no usual length yet', (tester) async {
      await pumpApp(
        tester,
        AnalysisScreen(data: analysisFrom([aDate(2024, 1, 1)])),
      );
      expect(find.textContaining('before your usual length'), findsOneWidget);
    });

    testWidgets('states the usual length and what it rests on', (tester) async {
      await pumpApp(
        tester,
        AnalysisScreen(
          data: analysisFrom(
            regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 4),
          ),
        ),
      );

      expect(find.text('28 days'), findsWidgets);
      // Never a bare average: how much data it rests on is part of the claim.
      expect(find.text('Based on your most recent 3 cycles'), findsOneWidget);
    });

    testWidgets('describes variation without naming the person', (
      tester,
    ) async {
      await pumpApp(
        tester,
        AnalysisScreen(
          data: analysisFrom([
            aDate(2024, 1, 1),
            aDate(2024, 1, 25), // 24
            aDate(2024, 2, 26), // 32
            aDate(2024, 3, 25),
          ]),
        ),
      );

      expect(find.textContaining('Between 24 and'), findsOneWidget);
      // Section 8: the data varies, she is not "irregular".
      expect(find.textContaining('irregular'), findsNothing);
    });

    testWidgets('says so plainly when every cycle matched', (tester) async {
      await pumpApp(
        tester,
        AnalysisScreen(
          data: analysisFrom(
            regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 4),
          ),
        ),
      );
      expect(
        find.text('Your cycles have been about the same length'),
        findsOneWidget,
      );
    });

    testWidgets('marks the current cycle as unfinished', (tester) async {
      await pumpApp(
        tester,
        AnalysisScreen(
          data: analysisFrom([aDate(2024, 1, 1), aDate(2024, 1, 29)]),
        ),
      );
      expect(find.text('In progress'), findsOneWidget);
    });

    testWidgets('renders in German', (tester) async {
      await pumpApp(
        tester,
        AnalysisScreen(
          data: analysisFrom(
            regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 4),
          ),
        ),
        locale: const Locale('de'),
      );
      expect(find.text('Übliche Länge'), findsOneWidget);
      expect(find.text('28 Tage'), findsWidgets);
    });

    testWidgets('does not overflow at 200% text', (tester) async {
      await pumpApp(
        tester,
        AnalysisScreen(
          data: analysisFrom(
            regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 5),
          ),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('in pregnancy', () {
    testWidgets('hides the figures but keeps the history', (tester) async {
      final data = analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 4),
        statisticsVisible: false,
      );
      await pumpApp(tester, AnalysisScreen(data: data));

      expect(find.textContaining('hidden during pregnancy'), findsOneWidget);
      expect(find.text('Usual length'), findsNothing);
      expect(find.text('Cycle lengths'), findsNothing);
      // The history is description, not statistics: it stays.
      expect(find.textContaining('Started Jan 1, 2024'), findsOneWidget);
    });
  });
}
