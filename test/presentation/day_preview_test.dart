import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/calendar/calendar_markers.dart';
import 'package:period/presentation/calendar/day_preview.dart';

import '../support/dates.dart';
import '../support/models.dart';
import '../support/widgets.dart';

void main() {
  final today = aDate(2024, 5, 17);

  final full = DayPreviewData(
    date: aDate(2024, 5, 4),
    today: today,
    isPeriodStart: true,
    marker: CalendarMarker.period,
    cycleDay: 1,
    entry: aDayEntry(
      date: aDate(2024, 5, 4),
      flow: FlowIntensity.medium,
      symptoms: {
        aSymptom(key: 'cramps'),
        aSymptom(key: 'headache'),
        aSymptom(key: 'mood.sensitive'),
      },
      note: 'Stayed in, lots of tea.',
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    DayPreviewData data, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
    VoidCallback? onEdit,
  }) => pumpApp(
    tester,
    Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          child: DayPreview(data: data, onEdit: onEdit ?? () {}),
        ),
      ),
    ),
    brightness: brightness,
    locale: locale,
    surface: const Size(400, 600),
  );

  testWidgets('lists everything logged, with Edit', (tester) async {
    await pump(tester, full);
    expect(find.text('Saturday, May 4'), findsOneWidget);
    expect(find.text('Cycle day 1'), findsOneWidget);
    expect(find.text('Period start'), findsOneWidget);
    expect(find.text('Flow: Medium'), findsOneWidget);
    expect(find.text('Cramps, Headache'), findsOneWidget);
    expect(find.text('Mood: Sensitive'), findsOneWidget);
    expect(find.text('Stayed in, lots of tea.'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('Edit reports the tap', (tester) async {
    var edits = 0;
    await pump(tester, full, onEdit: () => edits++);
    await tester.tap(find.text('Edit'));
    expect(edits, 1);
  });

  testWidgets('an empty past day offers to add an entry', (tester) async {
    await pump(tester, DayPreviewData(date: aDate(2024, 5, 9), today: today));
    expect(find.text('Nothing logged'), findsOneWidget);
    expect(find.text('Add entry'), findsOneWidget);
  });

  testWidgets('a fertile day carries the caveat', (tester) async {
    await pump(
      tester,
      DayPreviewData(
        date: aDate(2024, 5, 20),
        today: today,
        marker: CalendarMarker.fertile,
      ),
    );
    expect(
      find.textContaining('Not suitable for preventing pregnancy'),
      findsOneWidget,
    );
    expect(find.text('Add entry'), findsNothing);
  });

  group('goldens', () {
    testWidgets('a logged day', (tester) async {
      await pump(tester, full);
      await expectLater(
        find.byType(DayPreview),
        matchesGoldenFile('goldens/day_preview_logged.png'),
      );
    });

    testWidgets('a logged day, dark and German', (tester) async {
      await pump(
        tester,
        full,
        brightness: Brightness.dark,
        locale: const Locale('de'),
      );
      await expectLater(
        find.byType(DayPreview),
        matchesGoldenFile('goldens/day_preview_dark_german.png'),
      );
    });

    testWidgets('an estimated day still to come', (tester) async {
      await pump(
        tester,
        DayPreviewData(
          date: aDate(2024, 5, 29),
          today: today,
          marker: CalendarMarker.estimated,
        ),
      );
      await expectLater(
        find.byType(DayPreview),
        matchesGoldenFile('goldens/day_preview_estimated.png'),
      );
    });
  });
}
