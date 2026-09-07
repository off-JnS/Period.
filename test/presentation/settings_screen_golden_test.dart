import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/widgets.dart';

/// Pictures of the settings screen. Regenerate deliberately with
/// `flutter test --update-goldens` and read the diff before accepting it.
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    SettingsViewData data,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      SettingsScreen(
        data: data,
        onModeChanged: (_) {},
        onPredictionsOptInChanged: ({required optedIn}) {},
        onFertileWindowChanged: ({required optedIn}) {},
        onDeleteEverything: () {},
      ),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      // Taller than the other screens: this one is a list of choices and the
      // whole list is the thing worth looking at.
      surface: const Size(400, 1100),
    );
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_$name.png'),
    );
  }

  const natural = SettingsViewData();
  const perimenopause = SettingsViewData(
    cycle: CycleSettings(mode: CycleMode.perimenopause),
    fertileWindowOptedIn: true,
  );

  testWidgets('a natural cycle, the default', (tester) async {
    await expectGolden(tester, natural, 'natural');
  });

  testWidgets('pregnancy', (tester) async {
    await expectGolden(
      tester,
      const SettingsViewData(cycle: CycleSettings(mode: CycleMode.pregnancy)),
      'pregnancy',
    );
  });

  testWidgets('perimenopause, where the opt-in appears', (tester) async {
    await expectGolden(tester, perimenopause, 'perimenopause');
  });

  testWidgets('German', (tester) async {
    await expectGolden(
      tester,
      perimenopause,
      'german',
      locale: const Locale('de'),
    );
  });

  testWidgets('dark', (tester) async {
    await expectGolden(tester, natural, 'dark', brightness: Brightness.dark);
  });

  testWidgets('at twice the text size', (tester) async {
    await expectGolden(tester, natural, 'large_text', textScale: 2);
  });

  testWidgets('the confirmation before deleting', (tester) async {
    await pumpApp(
      tester,
      SettingsScreen(
        data: natural,
        onModeChanged: (_) {},
        onDeleteEverything: () {},
      ),
      surface: const Size(400, 1100),
    );
    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/settings_delete_confirm.png'),
    );
  });
}
