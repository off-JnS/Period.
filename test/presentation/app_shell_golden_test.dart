import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/presentation/app_shell.dart';
import 'package:period/presentation/providers.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/widgets.dart';

/// Golden tests for the shell, which is to say for the navigation bar.
///
/// Every screen had goldens; the bar between them did not, because it is not a
/// screen. That gap is not harmless. A design review of this app read the bar
/// by rendering it into a throwaway test and reported two critical faults in
/// it, and both were wrong -- there was no committed image to check them
/// against. These are that image.
///
/// German at enlarged text is the case worth keeping: "Einstellungen" is a
/// single word with nowhere to break, so above about 1.3x it splits mid-word
/// and the settings icon rides higher than the other three. That is real and it
/// is in this golden deliberately. It is not worth fixing: shortening the label
/// means abandoning the word every German app uses for settings, and clamping
/// the labels smaller takes size away from the users who asked for it. Flutter
/// already caps navigation labels at 1.3x for this reason
/// (navigation_bar.dart, _kMaxLabelTextScaleFactor), which is why 2x and 1.3x
/// look identical.
///
/// Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
void main() {
  late AppDatabase db;

  setUp(() => db = aDatabase());
  tearDown(() => db.close());

  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    double textScale = 1,
  }) async {
    await pumpWithDatabase(
      tester,
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const AppShell(),
      ),
      database: db,
      locale: const Locale('de'),
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(FixedClock(aDate(2024, 5, 17))),
      ],
    );
    // The whole shell, not just the bar: without a RepaintBoundary of its
    // own a finder captures the layer it sits in, and the bar has none. Seeing
    // it in context is better anyway -- the bar's height is only a problem
    // relative to the screen above it.
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/shell_$name.png'),
    );
  }

  testWidgets('German', (tester) async {
    await expectGolden(tester, 'german');
  });

  testWidgets('German at 200% text size', (tester) async {
    await expectGolden(tester, 'german_large_text', textScale: 2);
  });
}
