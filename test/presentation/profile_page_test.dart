import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/presentation/profile/profile_page.dart';
import 'package:period/presentation/profile/profile_screen.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/widgets.dart';

/// Through the real DAO, so what is checked is that a tap is actually stored.
void main() {
  late AppDatabase database;
  late int affected;

  setUp(() {
    database = aDatabase();
    affected = 0;
  });
  tearDown(() => database.close());

  Future<Profile> stored() => database.settingsDao.profile(currentYear: 2024);

  Future<void> pumpPage(WidgetTester tester, {bool withSettings = false}) =>
      pumpApp(
        tester,
        ProfilePage(
          settingsDao: database.settingsDao,
          clock: FixedClock(aDate(2024, 5, 17)),
          onScheduleAffected: () => affected++,
          settingsPage: withSettings
              ? (backLabel) => Scaffold(body: Text('Settings from $backLabel'))
              : null,
        ),
        // Tall enough that the mode list below About me is on screen.
        surface: const Size(400, 1800),
      );

  group('the cycle mode', () {
    testWidgets('opens on what is stored', (tester) async {
      await database.settingsDao.saveCycleSettings(
        const CycleSettings(mode: CycleMode.hormonalContraception),
      );
      await pumpPage(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Hormonal contraception')),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
      );
    });

    testWidgets('a chosen mode is saved at once and reschedules', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.bySemanticsLabel('Pregnancy'));
      await tester.pumpAndSettle();

      expect(
        (await database.settingsDao.cycleSettings()).mode,
        CycleMode.pregnancy,
      );
      expect(affected, 1);
    });

    testWidgets('the fertile window opt-in is saved', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Estimated fertile window'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(
        (await database.settingsDao.cycleSettings()).fertileWindowOptedIn,
        isTrue,
      );
    });

    testWidgets('a saved choice is still there after reopening', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.bySemanticsLabel('Perimenopause'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show estimates anyway'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Perimenopause')),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
      );
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Show estimates anyway'),
      );
      expect(tile.value, isTrue);
    });
  });

  group('about me', () {
    testWidgets('opens on what is stored', (tester) async {
      await database.settingsDao.saveProfile(
        const Profile(birthYear: 1996, usualCycleLength: 32),
      );
      await pumpPage(tester);
      expect(find.text('Turning 28 this year'), findsOneWidget);
      expect(find.text('1996'), findsOneWidget);
      expect(find.text('32 days'), findsOneWidget);
    });

    testWidgets('a birth year is saved only once Done is tapped', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(ProfileKeys.birthYear));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(ProfileKeys.wheel), const Offset(0, -72));
      await tester.pumpAndSettle();
      expect(await stored(), const Profile());

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      // The wheel starts at 25 years old and moved two rows older.
      expect((await stored()).birthYear, 2024 - 25 - 2);
      expect(find.text('Turning 27 this year'), findsOneWidget);
    });

    testWidgets('tapping outside the wheel keeps things as they were', (
      tester,
    ) async {
      await database.settingsDao.saveProfile(const Profile(birthYear: 1990));
      await pumpPage(tester);
      await tester.tap(find.byKey(ProfileKeys.birthYear));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(ProfileKeys.wheel), const Offset(0, -72));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();

      expect((await stored()).birthYear, 1990);
    });

    testWidgets('Clear removes an answer', (tester) async {
      await database.settingsDao.saveProfile(
        const Profile(usualPeriodLength: 6),
      );
      await pumpPage(tester);
      await tester.tap(find.byKey(ProfileKeys.periodLength));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(await stored(), const Profile());
    });

    testWidgets('a contraception method is saved, and a hormonal one offers '
        'the contraception mode without switching', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(ProfileKeys.contraception));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Hormonal IUD'));
      await tester.pumpAndSettle();

      expect((await stored()).contraception, ContraceptionMethod.hormonalIud);
      expect(
        find.textContaining('Switch to the contraception mode?'),
        findsOne,
      );
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
      expect(
        find.textContaining('Switch to the contraception mode?'),
        findsNothing,
      );
      expect(affected, 1);
    });

    testWidgets('conditions are saved as they are ticked', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(ProfileKeys.conditions));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('PCOS'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Endometriosis'));
      await tester.pumpAndSettle();
      expect((await stored()).conditions, {
        KnownCondition.pcos,
        KnownCondition.endometriosis,
      });

      await tester.tap(find.bySemanticsLabel('PCOS'));
      await tester.pumpAndSettle();
      expect((await stored()).conditions, {KnownCondition.endometriosis});

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Endometriosis'), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('opens from the gear, with Profile as the way back', (
      tester,
    ) async {
      await pumpPage(tester, withSettings: true);
      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings from Profile'), findsOneWidget);
    });

    testWidgets('has no gear when there is no Settings to open', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(find.byIcon(CupertinoIcons.gear_alt), findsNothing);
    });
  });
}
