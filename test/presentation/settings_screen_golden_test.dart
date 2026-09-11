import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/reminder_schedule.dart';
import 'package:period/domain/models/reminder_time.dart';
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
        onAppLockChanged: ({required enabled}) {},
        onReminderChanged: (_) {},
      ),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
      // Taller than the other screens: this one is a list of choices and the
      // whole list is the thing worth looking at, and a picture that cut off
      // the bottom of it would quietly stop reviewing whatever fell below.
      surface: const Size(400, 1550),
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

  /// The whole settings list with the reminder section open.
  ///
  /// Separate from [expectGolden] because the section only appears once the
  /// reminder is on, and because the list is then taller than the surface the
  /// other pictures use -- so the time row and the weekday chips, which are the
  /// whole subject here, would fall off the bottom of them.
  Future<void> expectReminderGolden(
    WidgetTester tester,
    ReminderSchedule reminder,
    String name, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    bool remindersAllowed = true,
    Size surface = const Size(400, 1800),
  }) async {
    await pumpApp(
      tester,
      SettingsScreen(
        remindersAllowed: remindersAllowed,
        data: SettingsViewData(reminder: reminder),
        onModeChanged: (_) {},
        onPredictionsOptInChanged: ({required optedIn}) {},
        onFertileWindowChanged: ({required optedIn}) {},
        onDeleteEverything: () {},
        onExportBackup: () {},
        onRestoreBackup: () {},
        onAppLockChanged: ({required enabled}) {},
        onReminderChanged: (_) {},
      ),
      locale: locale,
      textScale: textScale,
      // Tall enough to hold the whole list with the reminder section open. A
      // scroll would work too and would be worse: where it stopped would decide
      // what the picture showed, and the point of these is to see the section
      // whole.
      surface: surface,
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_$name.png'),
    );
  }

  testWidgets('the reminder, on and daily', (tester) async {
    await expectReminderGolden(
      tester,
      const ReminderSchedule(enabled: true),
      'reminder_daily',
    );
  });

  testWidgets('the reminder on a few days a week, in German', (tester) async {
    // German plus a row of weekday chips is the combination most likely to
    // overflow, and the one worth a picture.
    await expectReminderGolden(
      tester,
      const ReminderSchedule(
        enabled: true,
        time: ReminderTime(7, 30),
        weekdays: {1, 3, 5},
      ),
      'reminder_weekly_german',
      locale: const Locale('de'),
    );
  });

  testWidgets('the reminder with no day selected', (tester) async {
    // On, and nothing will ever fire. The warning is the whole subject.
    await expectReminderGolden(
      tester,
      const ReminderSchedule(enabled: true, weekdays: {}),
      'reminder_no_days',
    );
  });

  testWidgets('the reminder the system is blocking', (tester) async {
    // She asked for it and the phone will not deliver it. The picture is worth
    // having because this is the state a user actually complains about, and
    // because it is the only one where the app has to explain something that
    // is not its own doing.
    await expectReminderGolden(
      tester,
      const ReminderSchedule(enabled: true),
      'reminder_blocked',
      remindersAllowed: false,
    );
  });

  testWidgets('the reminder at twice the text size', (tester) async {
    await expectReminderGolden(
      tester,
      const ReminderSchedule(enabled: true, weekdays: {2, 6}),
      'reminder_large_text',
      textScale: 2,
      surface: const Size(400, 3000),
    );
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
        onAppLockChanged: ({required enabled}) {},
        onReminderChanged: (_) {},
      ),
      // Tall enough to reach the delete tile. The list is lazy, so a shorter
      // surface does not merely hide it -- it is never built, and the tap below
      // fails finding nothing.
      surface: const Size(400, 1550),
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
