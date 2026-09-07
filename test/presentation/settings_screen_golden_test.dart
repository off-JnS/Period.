import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/settings/passphrase_dialog.dart';
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
        onExportBackup: () {},
        onRestoreBackup: () {},
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

  Future<void> expectDialogGolden(
    WidgetTester tester,
    String tap,
    String name,
  ) async {
    await pumpApp(
      tester,
      SettingsScreen(
        data: natural,
        onModeChanged: (_) {},
        onDeleteEverything: () {},
        onExportBackup: () {},
        onRestoreBackup: () {},
      ),
      surface: const Size(400, 1100),
    );
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/settings_$name.png'),
    );
  }

  testWidgets('the confirmation before deleting', (tester) async {
    await expectDialogGolden(tester, 'Delete all data', 'delete_confirm');
  });

  testWidgets('choosing a backup passphrase', (tester) async {
    // The screen where the app tells her the one thing she must not forget.
    await pumpApp(
      tester,
      const PassphraseDialogHarness(confirming: true),
      surface: const Size(400, 700),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/settings_passphrase_new.png'),
    );
  });

  testWidgets('entering a passphrase to restore', (tester) async {
    await pumpApp(
      tester,
      const PassphraseDialogHarness(confirming: false),
      surface: const Size(400, 700),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/settings_passphrase_enter.png'),
    );
  });
}

/// Shows [PassphraseDialog] on its own, so it can be photographed without
/// driving the whole export flow to reach it.
class PassphraseDialogHarness extends StatelessWidget {
  /// Creates the harness.
  const PassphraseDialogHarness({required this.confirming, super.key});

  /// Passed straight through.
  final bool confirming;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: PassphraseDialog(confirming: confirming));
}
