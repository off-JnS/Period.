import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/widgets.dart';

/// The settings screen as a pure widget.
void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    SettingsViewData data = const SettingsViewData(),
    void Function(CycleMode)? onModeChanged,
    void Function({required bool optedIn})? onPredictionsOptInChanged,
    void Function({required bool optedIn})? onFertileWindowChanged,
    VoidCallback? onDeleteEverything,
    void Function({required bool enabled})? onAppLockChanged,
    bool lockAvailable = true,
    Locale locale = const Locale('en'),
  }) async {
    await pumpApp(
      tester,
      // Tall enough to lay the whole list out. A ListView does not build what
      // is below the fold, so at the default height these finders would miss
      // the rows at the bottom and report them as absent rather than offscreen.
      // The real height is what the goldens check.
      surface: const Size(400, 1500),
      SettingsScreen(
        data: data,
        onModeChanged: onModeChanged ?? (_) {},
        onPredictionsOptInChanged:
            onPredictionsOptInChanged ?? ({required optedIn}) {},
        onFertileWindowChanged:
            onFertileWindowChanged ?? ({required optedIn}) {},
        onDeleteEverything: onDeleteEverything ?? () {},
        onExportBackup: () {},
        onRestoreBackup: () {},
        onAppLockChanged: onAppLockChanged ?? ({required enabled}) {},
        lockAvailable: lockAvailable,
      ),
      locale: locale,
    );
  }

  group('choosing a mode', () {
    testWidgets('every mode is offered', (tester) async {
      await pumpSettings(tester);
      for (final label in [
        'A natural cycle',
        'Hormonal contraception',
        'Pregnant',
        'Perimenopause',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('each one says what it does to estimates', (tester) async {
      // Section 10 requires every mode to state why estimates are off. Saying
      // it only on the Today screen would leave her choosing blind here.
      await pumpSettings(tester);
      expect(
        find.textContaining('follows your regimen rather than a cycle'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Everything you log is still saved'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cycle lengths often change a lot'),
        findsOneWidget,
      );
    });

    testWidgets('reports the mode that was chosen', (tester) async {
      CycleMode? chosen;
      await pumpSettings(tester, onModeChanged: (mode) => chosen = mode);

      await tester.tap(find.text('Pregnant'));
      expect(chosen, CycleMode.pregnancy);
    });

    testWidgets('the current mode is the selected one', (tester) async {
      await pumpSettings(
        tester,
        data: const SettingsViewData(
          cycle: CycleSettings(mode: CycleMode.pregnancy),
        ),
      );

      final selected = tester
          .widgetList<RadioListTile<CycleMode>>(
            find.byType(RadioListTile<CycleMode>),
          )
          .where((tile) => tile.value == CycleMode.pregnancy);
      expect(selected, hasLength(1));
      expect(
        tester
            .widget<RadioGroup<CycleMode>>(find.byType(RadioGroup<CycleMode>))
            .groupValue,
        CycleMode.pregnancy,
      );
    });

    testWidgets('no mode names a condition or diagnoses anything', (
      tester,
    ) async {
      // Section 8: the app must not become a regulated medical device, and that
      // line is crossed by claims. These are the words that would cross it.
      await pumpSettings(tester);
      for (final forbidden in [
        'disorder',
        'diagnos',
        'abnormal',
        'irregular',
        'infertile',
        'symptom of',
      ]) {
        expect(
          find.textContaining(RegExp(forbidden, caseSensitive: false)),
          findsNothing,
          reason: 'settings copy must not contain "$forbidden"',
        );
      }
    });
  });

  group('the estimates opt-in', () {
    testWidgets('appears only under perimenopause', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Show estimates anyway'), findsNothing);

      await pumpSettings(
        tester,
        data: const SettingsViewData(
          cycle: CycleSettings(mode: CycleMode.perimenopause),
        ),
      );
      expect(find.text('Show estimates anyway'), findsOneWidget);
    });

    testWidgets('is not offered for contraception or pregnancy', (
      tester,
    ) async {
      // Those two have no natural cycle to estimate from, so offering the
      // switch would imply an estimate exists to be turned on.
      for (final mode in [
        CycleMode.hormonalContraception,
        CycleMode.pregnancy,
      ]) {
        await pumpSettings(
          tester,
          data: SettingsViewData(cycle: CycleSettings(mode: mode)),
        );
        expect(find.text('Show estimates anyway'), findsNothing);
      }
    });

    testWidgets('says the estimates will be wide before she opts in', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        data: const SettingsViewData(
          cycle: CycleSettings(mode: CycleMode.perimenopause),
        ),
      );
      expect(find.textContaining('wide ranges'), findsOneWidget);
    });

    testWidgets('reports the change', (tester) async {
      bool? asked;
      await pumpSettings(
        tester,
        data: const SettingsViewData(
          cycle: CycleSettings(mode: CycleMode.perimenopause),
        ),
        onPredictionsOptInChanged: ({required optedIn}) => asked = optedIn,
      );

      await tester.tap(find.text('Show estimates anyway'));
      expect(asked, isTrue);
    });
  });

  group('the fertile window', () {
    testWidgets('is off unless asked for', (tester) async {
      await pumpSettings(tester);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Show the fertile window estimate'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('carries the caveat beside the switch, not after it', (
      tester,
    ) async {
      // Section 8 requires the note wherever the window appears. The moment it
      // matters most is before she turns it on.
      await pumpSettings(tester);
      expect(
        find.textContaining('Not suitable for preventing pregnancy'),
        findsOneWidget,
      );
    });

    testWidgets('reports the change', (tester) async {
      var turnedOn = false;
      await pumpSettings(
        tester,
        onFertileWindowChanged: ({required optedIn}) => turnedOn = optedIn,
      );

      await tester.tap(find.text('Show the fertile window estimate'));
      expect(turnedOn, isTrue);
    });
  });

  group('the app lock', () {
    testWidgets('is off unless asked for', (tester) async {
      await pumpSettings(tester);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Ask before opening the app'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('says it uses the phone\'s own lock and will not trap her', (
      tester,
    ) async {
      // Both facts belong beside the switch: the app keeps no PIN of its own,
      // and a phone with no lock set opens the app rather than shutting her
      // out of her own data.
      await pumpSettings(tester);
      expect(
        find.textContaining('Uses whatever unlocks your phone'),
        findsOneWidget,
      );
      expect(
        find.textContaining('opens as usual rather than shutting you out'),
        findsOneWidget,
      );
    });

    testWidgets('explains itself when the phone cannot authenticate', (
      tester,
    ) async {
      await pumpSettings(tester, lockAvailable: false);

      expect(find.textContaining('no lock set'), findsOneWidget);
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Ask before opening the app'),
      );
      expect(
        tile.onChanged,
        isNull,
        reason: 'a switch that cannot do anything must not look like it can',
      );
    });

    testWidgets('reports the change', (tester) async {
      bool? asked;
      await pumpSettings(
        tester,
        onAppLockChanged: ({required enabled}) => asked = enabled,
      );

      await tester.tap(find.text('Ask before opening the app'));
      expect(asked, isTrue);
    });
  });

  group('deleting everything', () {
    testWidgets('asks first', (tester) async {
      var deleted = false;
      await pumpSettings(tester, onDeleteEverything: () => deleted = true);

      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      expect(find.text('Delete everything?'), findsOneWidget);
      expect(deleted, isFalse);
    });

    testWidgets('says exactly what goes, including the settings', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();

      expect(find.textContaining('setting'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      var deleted = false;
      await pumpSettings(tester, onDeleteEverything: () => deleted = true);

      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(deleted, isFalse);
    });

    testWidgets('confirming deletes', (tester) async {
      var deleted = false;
      await pumpSettings(tester, onDeleteEverything: () => deleted = true);

      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });

  testWidgets('states the promise the app is built on', (tester) async {
    await pumpSettings(tester);
    expect(find.textContaining('stays on this device'), findsOneWidget);
    expect(find.textContaining('there is no account'), findsOneWidget);
  });

  testWidgets('German', (tester) async {
    await pumpSettings(tester, locale: const Locale('de'));
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Schwanger'), findsOneWidget);
    expect(find.text('Alle Daten löschen'), findsOneWidget);
  });
}
