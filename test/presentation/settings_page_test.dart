import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/settings/settings_page.dart';

import '../support/database.dart';
import '../support/widgets.dart';

/// Through the real DAO, so what is checked is that a tap is actually stored.
void main() {
  late AppDatabase database;

  setUp(() => database = aDatabase());
  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester) =>
      pumpApp(tester, SettingsPage(settingsDao: database.settingsDao));

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

  testWidgets('a chosen mode is saved at once, with no Save button', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.bySemanticsLabel('Pregnancy'));
    await tester.pumpAndSettle();

    expect(
      (await database.settingsDao.cycleSettings()).mode,
      CycleMode.pregnancy,
    );
  });

  testWidgets('the fertile window opt-in is saved', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Estimated fertile window'));
    await tester.pumpAndSettle();

    expect(
      (await database.settingsDao.cycleSettings()).fertileWindowOptedIn,
      isTrue,
    );
  });

  testWidgets('a saved choice is still there after reopening', (tester) async {
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

  testWidgets('a chosen appearance is stored, then handed to the app', (
    tester,
  ) async {
    final applied = <AppPreferences>[];
    await pumpApp(
      tester,
      SettingsPage(
        settingsDao: database.settingsDao,
        onPreferencesChanged: applied.add,
      ),
    );
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Dark'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.bySemanticsLabel('Dark'));
    await tester.pumpAndSettle();

    const expected = AppPreferences(appearance: AppearanceChoice.dark);
    expect(await database.settingsDao.appPreferences(), expected);
    expect(applied, [expected]);
  });
}
