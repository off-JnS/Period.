import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/presentation/profile/profile_screen.dart';

import '../support/widgets.dart';

/// Golden tests for Profile. Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens
void main() {
  const filled = Profile(
    birthYear: 1998,
    usualCycleLength: 30,
    usualPeriodLength: 5,
    contraception: ContraceptionMethod.copperIud,
    conditions: {KnownCondition.endometriosis},
  );

  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    Profile profile = const Profile(),
    CycleSettings settings = const CycleSettings(),
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    Size surface = const Size(400, 900),
  }) async {
    await pumpApp(
      tester,
      ProfileScreen(
        profile: profile,
        settings: settings,
        currentYear: 2026,
        onProfileChanged: (_) {},
        onSettingsChanged: (_) {},
        onOpenSettings: () {},
      ),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      surface: surface,
    );
    await expectLater(
      find.byType(ProfileScreen),
      matchesGoldenFile('goldens/profile_$name.png'),
    );
  }

  testWidgets('empty', (tester) async {
    await expectGolden(tester, 'empty');
  });

  testWidgets('filled in, the whole screen', (tester) async {
    await expectGolden(
      tester,
      'filled',
      profile: filled,
      surface: const Size(400, 1500),
    );
  });

  testWidgets('offering the contraception mode', (tester) async {
    await expectGolden(
      tester,
      'offer',
      profile: const Profile(
        birthYear: 2001,
        contraception: ContraceptionMethod.combinedPill,
      ),
    );
  });

  testWidgets('perimenopause with estimates back on', (tester) async {
    await expectGolden(
      tester,
      'perimenopause',
      profile: filled,
      settings: const CycleSettings(
        mode: CycleMode.perimenopause,
        predictionsOptedIn: true,
      ),
      surface: const Size(400, 1700),
    );
  });

  testWidgets('dark', (tester) async {
    await expectGolden(
      tester,
      'dark',
      profile: filled,
      brightness: Brightness.dark,
    );
  });

  testWidgets('German', (tester) async {
    await expectGolden(
      tester,
      'german',
      profile: filled,
      locale: const Locale('de'),
    );
  });

  testWidgets('at 200% text size', (tester) async {
    await expectGolden(tester, 'large_text', profile: filled, textScale: 2);
  });
}
