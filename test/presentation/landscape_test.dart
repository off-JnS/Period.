import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/analysis/analysis_page.dart';
import 'package:period/presentation/analysis/analysis_screen.dart';
import 'package:period/presentation/calendar/calendar_screen.dart';
import 'package:period/presentation/settings/settings_screen.dart';
import 'package:period/presentation/today/today_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// The app allows landscape (Info.plist), so every screen has to lay out in
/// it: an iPhone on its side is 874 by 402 points, and at large text sizes the
/// short side is where overflow shows first.
void main() {
  const landscape = Size(874, 402);

  final screens = <String, Widget>{
    'Today': TodayScreen(
      data: TodayViewData(
        cycleDay: 22,
        typicalCycleLength: 28,
        prediction: PredictedPeriod(
          earliest: aDate(2024, 4, 26),
          latest: aDate(2024, 4, 30),
        ),
      ),
      onAddEntry: () {},
    ),
    'Calendar': CalendarScreen(
      data: CalendarViewData(year: 2024, month: 5, today: aDate(2024, 5, 17)),
    ),
    'Your cycles': AnalysisScreen(
      data: analysisFrom(
        regularPeriodStarts(from: aDate(2024, 1, 1), length: 28, count: 5),
      ),
    ),
    'Settings': SettingsScreen(
      settings: const CycleSettings(),
      onChanged: (_) {},
    ),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('$name lays out in landscape at ${textScale}x text', (
        tester,
      ) async {
        await pumpApp(tester, screen, surface: landscape, textScale: textScale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
