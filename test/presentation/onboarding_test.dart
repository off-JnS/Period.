import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/presentation/onboarding/onboarding_flow.dart';
import 'package:period/presentation/profile/profile_screen.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/widgets.dart';

/// Through the real DAOs, so what is checked is what is actually stored.
void main() {
  late AppDatabase database;
  late int finished;

  setUp(() {
    database = aDatabase();
    finished = 0;
  });
  tearDown(() => database.close());

  final today = aDate(2026, 9, 28);

  Future<void> pumpFlow(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    Size surface = const Size(400, 860),
  }) => pumpApp(
    tester,
    OnboardingFlow(
      settingsDao: database.settingsDao,
      logDao: database.logDao,
      clock: FixedClock(today),
      onFinished: () => finished++,
    ),
    locale: locale,
    textScale: textScale,
    surface: surface,
  );

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(OnboardingKeys.next));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the welcome page with its three promises', (
    tester,
  ) async {
    await pumpFlow(tester);

    expect(find.text('Welcome to Period.'), findsOneWidget);
    expect(find.text('Stays on your phone'), findsOneWidget);
    expect(find.text('No account, no sign-in'), findsOneWidget);
    // The fertile-window caveat's rule applies to any estimate claim (§8).
    expect(
      find.textContaining('not suitable for contraception'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('the last page reassures until a day is picked', (tester) async {
    await pumpFlow(tester);
    await next(tester);
    await next(tester);

    expect(find.text('Choose a date'), findsOneWidget);
    expect(find.textContaining('Not sure?'), findsOneWidget);
  });

  testWidgets('walking through saves the profile, the first entry and done', (
    tester,
  ) async {
    await pumpFlow(tester);
    await next(tester);
    expect(find.text('About you'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);

    // Usual cycle: the wheel opens on 28; Done keeps it.
    await tester.tap(find.byKey(ProfileKeys.cycleLength));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      (await database.settingsDao.profile(currentYear: 2026)).usualCycleLength,
      28,
    );

    await next(tester);
    expect(find.text('When did your last period start?'), findsOneWidget);
    await tester.tap(find.byKey(OnboardingKeys.lastPeriod));
    await tester.pumpAndSettle();
    // The wheel starts on today, and cannot go past it.
    await tester.drag(
      find.byKey(OnboardingKeys.dateWheel),
      const Offset(0, 0),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('September 28'), findsOneWidget);
    expect(
      find.text('September 28 becomes your first period entry.'),
      findsOneWidget,
    );

    expect(find.text('Start tracking'), findsOneWidget);
    await next(tester);

    expect(await database.logDao.allPeriodStarts(), [today]);
    expect(await database.settingsDao.onboardingDone(), isTrue);
    expect(finished, 1);
  });

  testWidgets('finishing without a date adds no entry', (tester) async {
    await pumpFlow(tester);
    await next(tester);
    await next(tester);
    await next(tester);

    expect(await database.logDao.allPeriodStarts(), isEmpty);
    expect(await database.settingsDao.onboardingDone(), isTrue);
    expect(finished, 1);
  });

  testWidgets('skip on any page ends it and records it as done', (
    tester,
  ) async {
    await pumpFlow(tester);
    await next(tester);
    await tester.tap(find.byKey(OnboardingKeys.skip));
    await tester.pumpAndSettle();

    expect(await database.settingsDao.onboardingDone(), isTrue);
    expect(finished, 1);
  });

  testWidgets('skip on the last page drops a date she picked', (
    tester,
  ) async {
    await pumpFlow(tester);
    await next(tester);
    await next(tester);
    await tester.tap(find.byKey(OnboardingKeys.lastPeriod));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(OnboardingKeys.skip));
    await tester.pumpAndSettle();

    expect(await database.logDao.allPeriodStarts(), isEmpty);
    expect(finished, 1);
  });

  testWidgets('back returns to the previous page', (tester) async {
    await pumpFlow(tester);
    await next(tester);
    await tester.tap(find.byKey(OnboardingKeys.back));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Period.'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('a hormonal method offers the contraception mode, never sets it', (
    tester,
  ) async {
    await database.settingsDao.saveProfile(
      const Profile(contraception: ContraceptionMethod.combinedPill),
    );
    await pumpFlow(tester);
    await next(tester);

    expect(find.text('Switch'), findsOneWidget);
    expect(
      (await database.settingsDao.cycleSettings()).mode,
      CycleMode.natural,
    );

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(
      (await database.settingsDao.cycleSettings()).mode,
      CycleMode.hormonalContraception,
    );
  });

  testWidgets('opens on answers already stored', (tester) async {
    await database.settingsDao.saveProfile(const Profile(birthYear: 1998));
    await pumpFlow(tester);
    await next(tester);

    expect(find.text('1998'), findsOneWidget);
  });

  testWidgets('German', (tester) async {
    await pumpFlow(tester, locale: const Locale('de'));
    expect(find.text('Willkommen bei Period.'), findsOneWidget);
    expect(find.text('Los geht’s'), findsOneWidget);
  });

  testWidgets('every page fits at the largest text size', (tester) async {
    await pumpFlow(tester, textScale: 2, surface: const Size(400, 860));
    for (var page = 0; page < 3; page++) {
      expect(tester.takeException(), isNull);
      if (page < 2) await next(tester);
    }
    expect(find.byType(CupertinoButton), findsWidgets);
  });

  group('goldens', () {
    for (final (name, pages) in [('welcome', 0), ('about', 1), ('last', 2)]) {
      testWidgets(name, (tester) async {
        await pumpFlow(tester);
        for (var i = 0; i < pages; i++) {
          await next(tester);
        }
        await expectLater(
          find.byType(OnboardingFlow),
          matchesGoldenFile('goldens/onboarding_$name.png'),
        );
      });
    }

    testWidgets('welcome, dark', (tester) async {
      await pumpApp(
        tester,
        OnboardingFlow(
          settingsDao: database.settingsDao,
          logDao: database.logDao,
          clock: FixedClock(today),
          onFinished: () {},
        ),
        brightness: Brightness.dark,
        surface: const Size(400, 860),
      );
      await expectLater(
        find.byType(OnboardingFlow),
        matchesGoldenFile('goldens/onboarding_welcome_dark.png'),
      );
    });
  });
}
