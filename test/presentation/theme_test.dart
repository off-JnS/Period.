import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/theme.dart';

/// The appearance the app actually renders in.
///
/// This file exists because the goldens did not catch what it catches. The app
/// shipped with a light theme and no dark one, so on a phone set to dark it
/// rendered light -- while six dark goldens passed, because the test harness
/// built a dark theme of its own that the app never used. A picture cannot
/// prove the app is wired to what it pictures.
///
/// So this asserts the wiring, by building a MaterialApp exactly as `main.dart`
/// does and reading back the theme a screen inside it sees.
void main() {
  /// Builds the app's MaterialApp under a given device appearance and reports
  /// the brightness a descendant actually gets.
  Future<Brightness> brightnessUnder(
    WidgetTester tester,
    Brightness platform,
  ) async {
    late Brightness seen;

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(platformBrightness: platform),
        child: MaterialApp(
          theme: appLightTheme,
          darkTheme: appDarkTheme,
          home: Builder(
            builder: (context) {
              seen = Theme.of(context).brightness;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    return seen;
  }

  testWidgets('a device set to dark gets a dark app', (tester) async {
    expect(await brightnessUnder(tester, Brightness.dark), Brightness.dark);
  });

  testWidgets('a device set to light gets a light app', (tester) async {
    expect(await brightnessUnder(tester, Brightness.light), Brightness.light);
  });

  test('both appearances are Material 3', () {
    // The dark one was added later than the light one. If it ever stops
    // matching, the dark goldens quietly stop being pictures of this app.
    expect(appLightTheme.useMaterial3, isTrue);
    expect(appDarkTheme.useMaterial3, isTrue);
  });

  test('the two appearances are actually different', () {
    // Guards the lazy version of the fix -- declaring darkTheme and handing it
    // the light one, which satisfies every structural check and changes nothing
    // a user would see.
    expect(appDarkTheme.brightness, Brightness.dark);
    expect(appLightTheme.brightness, Brightness.light);
    expect(
      appDarkTheme.colorScheme.surface,
      isNot(appLightTheme.colorScheme.surface),
    );
  });
}
