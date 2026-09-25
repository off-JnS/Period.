import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/presentation/profile/profile_screen.dart';

import '../support/widgets.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    Profile profile = const Profile(),
    CycleSettings settings = const CycleSettings(),
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) => pumpApp(
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
    textScale: textScale,
  );

  const offer = 'Switch to the contraception mode?';

  testWidgets('asks for a little about her until there is a birth year', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Tell Period. a little about you'), findsOneWidget);
    expect(find.text('Not set'), findsNWidgets(5));
  });

  testWidgets('shows the age she turns this year, never a birthday', (
    tester,
  ) async {
    await pumpScreen(tester, profile: const Profile(birthYear: 1998));
    expect(find.text('Turning 28 this year'), findsOneWidget);
  });

  testWidgets('shows her mode under the avatar', (tester) async {
    await pumpScreen(
      tester,
      settings: const CycleSettings(mode: CycleMode.perimenopause),
    );
    expect(find.text('Perimenopause'), findsWidgets);
  });

  testWidgets('says none of it feeds an estimate', (tester) async {
    await pumpScreen(tester);
    expect(
      find.textContaining('Estimates use what you log, never these answers'),
      findsOneWidget,
    );
  });

  testWidgets('summarises one condition by name and several by count', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      profile: const Profile(conditions: {KnownCondition.pmdd}),
    );
    expect(find.text('PMDD'), findsOneWidget);

    await pumpScreen(
      tester,
      profile: const Profile(
        conditions: {KnownCondition.pmdd, KnownCondition.fibroids},
      ),
    );
    expect(find.text('2 conditions'), findsOneWidget);
  });

  group('the contraception offer', () {
    testWidgets('appears for a hormonal method in the natural mode', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        profile: const Profile(contraception: ContraceptionMethod.implant),
      );
      expect(find.textContaining(offer), findsOneWidget);
    });

    testWidgets('stays away for a copper IUD', (tester) async {
      await pumpScreen(
        tester,
        profile: const Profile(contraception: ContraceptionMethod.copperIud),
      );
      expect(find.textContaining(offer), findsNothing);
    });

    testWidgets('stays away once in another mode', (tester) async {
      await pumpScreen(
        tester,
        profile: const Profile(contraception: ContraceptionMethod.ring),
        settings: const CycleSettings(mode: CycleMode.pregnancy),
      );
      expect(find.textContaining(offer), findsNothing);
    });
  });

  testWidgets('German fits at 200% text size', (tester) async {
    await pumpScreen(
      tester,
      profile: const Profile(
        birthYear: 1990,
        usualCycleLength: 30,
        usualPeriodLength: 5,
        contraception: ContraceptionMethod.progestinPill,
        conditions: {KnownCondition.thyroid},
      ),
      locale: const Locale('de'),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Du wirst dieses Jahr 36'), findsOneWidget);
  });
}
