import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/widgets.dart';

void main() {
  Future<List<CycleSettings>> pumpScreen(
    WidgetTester tester,
    CycleSettings settings, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    final changes = <CycleSettings>[];
    await pumpApp(
      tester,
      SettingsScreen(settings: settings, onChanged: changes.add),
      locale: locale,
      textScale: textScale,
    );
    return changes;
  }

  Finder modeRow(String label) => find.bySemanticsLabel(label);

  group('the mode list', () {
    testWidgets('offers all four modes', (tester) async {
      await pumpScreen(tester, const CycleSettings());
      for (final label in [
        'Natural cycle',
        'Hormonal contraception',
        'Pregnancy',
        'Perimenopause',
      ]) {
        expect(modeRow(label), findsOneWidget);
      }
    });

    testWidgets('marks the current mode with a checkmark, not colour alone', (
      tester,
    ) async {
      await pumpScreen(tester, const CycleSettings(mode: CycleMode.pregnancy));
      // One checkmark per list; the mode list's is on Pregnancy.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Pregnancy'),
            matching: find.byType(InkWell),
          ),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(modeRow('Pregnancy')),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
      );
      expect(
        tester.getSemantics(modeRow('Natural cycle')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
    });

    testWidgets('choosing a mode reports it and keeps the opt-ins', (
      tester,
    ) async {
      final changes = await pumpScreen(
        tester,
        const CycleSettings(fertileWindowOptedIn: true),
      );
      await tester.tap(modeRow('Perimenopause'));
      await tester.pump();

      expect(changes, [
        const CycleSettings(
          mode: CycleMode.perimenopause,
          fertileWindowOptedIn: true,
        ),
      ]);
    });

    testWidgets('tapping the current mode changes nothing', (tester) async {
      final changes = await pumpScreen(tester, const CycleSettings());
      await tester.tap(modeRow('Natural cycle'));
      await tester.pump();
      expect(changes, isEmpty);
    });

    testWidgets('every mode explains itself', (tester) async {
      // Section 10: predictions-off is a state to be stated.
      final footers = {
        CycleMode.natural: 'estimated from the cycles you log',
        CycleMode.hormonalContraception: 'follows your regimen',
        CycleMode.pregnancy: 'cycle figures are hidden',
        CycleMode.perimenopause: 'unless you turn them on',
      };
      for (final MapEntry(key: mode, value: phrase) in footers.entries) {
        await pumpScreen(tester, CycleSettings(mode: mode));
        expect(find.textContaining(phrase), findsOneWidget, reason: '$mode');
      }
    });
  });

  group('the perimenopause estimates switch', () {
    testWidgets('appears only in perimenopause', (tester) async {
      for (final mode in CycleMode.values) {
        await pumpScreen(tester, CycleSettings(mode: mode));
        expect(
          find.text('Show estimates anyway'),
          mode == CycleMode.perimenopause ? findsOneWidget : findsNothing,
          reason: '$mode',
        );
      }
    });

    testWidgets('turning it on reports the opt-in', (tester) async {
      final changes = await pumpScreen(
        tester,
        const CycleSettings(mode: CycleMode.perimenopause),
      );
      await tester.tap(find.text('Show estimates anyway'));
      await tester.pump();
      expect(changes.single.predictionsOptedIn, isTrue);
      expect(changes.single.mode, CycleMode.perimenopause);
    });
  });

  group('the fertile window switch', () {
    testWidgets('is off by default', (tester) async {
      await pumpScreen(tester, const CycleSettings());
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Estimated fertile window'),
      );
      expect(tile.value, isFalse);
    });

    testWidgets('always shows its caveat beside it', (tester) async {
      // Section 8: visible before she turns it on, never behind a tap.
      await pumpScreen(tester, const CycleSettings());
      expect(
        find.textContaining('Not suitable for preventing pregnancy'),
        findsOneWidget,
      );
    });

    testWidgets('is offered only where there is an estimate to count from', (
      tester,
    ) async {
      final offered = {
        const CycleSettings(): true,
        const CycleSettings(mode: CycleMode.hormonalContraception): false,
        const CycleSettings(mode: CycleMode.pregnancy): false,
        const CycleSettings(mode: CycleMode.perimenopause): false,
        const CycleSettings(
          mode: CycleMode.perimenopause,
          predictionsOptedIn: true,
        ): true,
      };
      for (final MapEntry(key: settings, value: shown) in offered.entries) {
        await pumpScreen(tester, settings);
        expect(
          find.text('Estimated fertile window'),
          shown ? findsOneWidget : findsNothing,
          reason: '$settings',
        );
      }
    });

    testWidgets('turning it on reports the opt-in', (tester) async {
      final changes = await pumpScreen(tester, const CycleSettings());
      await tester.tap(find.text('Estimated fertile window'));
      await tester.pump();
      expect(changes, [const CycleSettings(fertileWindowOptedIn: true)]);
    });
  });

  testWidgets('restates that settings stay encrypted on the device', (
    tester,
  ) async {
    await pumpScreen(tester, const CycleSettings());
    await tester.scrollUntilVisible(
      find.textContaining('stored encrypted on this device'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('stored encrypted on this device'),
      findsOneWidget,
    );
  });

  testWidgets('German fits at 200% text size', (tester) async {
    await pumpScreen(
      tester,
      const CycleSettings(mode: CycleMode.perimenopause),
      locale: const Locale('de'),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Trotzdem Schätzungen zeigen'), findsOneWidget);
  });

  group('appearance and language', () {
    Future<List<AppPreferences>> pumpWithPreferences(
      WidgetTester tester,
      AppPreferences preferences, {
      Locale locale = const Locale('en'),
    }) async {
      final changes = <AppPreferences>[];
      await pumpApp(
        tester,
        SettingsScreen(
          settings: const CycleSettings(),
          onChanged: (_) {},
          preferences: preferences,
          onPreferencesChanged: changes.add,
        ),
        locale: locale,
      );
      return changes;
    }

    Future<void> scrollTo(WidgetTester tester, Finder finder) =>
        tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('choosing Dark reports it and keeps the language', (
      tester,
    ) async {
      final changes = await pumpWithPreferences(
        tester,
        const AppPreferences(language: LanguageChoice.german),
        locale: const Locale('de'),
      );
      await scrollTo(tester, find.bySemanticsLabel('Dunkel'));
      await tester.tap(find.bySemanticsLabel('Dunkel'));
      await tester.pump();

      expect(changes, [
        const AppPreferences(
          appearance: AppearanceChoice.dark,
          language: LanguageChoice.german,
        ),
      ]);
    });

    testWidgets('choosing a language reports it', (tester) async {
      final changes = await pumpWithPreferences(tester, const AppPreferences());
      await scrollTo(tester, find.bySemanticsLabel('Deutsch'));
      await tester.tap(find.bySemanticsLabel('Deutsch'));
      await tester.pump();

      expect(changes, [const AppPreferences(language: LanguageChoice.german)]);
    });

    testWidgets('each language is named in itself, whatever the app shows', (
      tester,
    ) async {
      // Someone who switched to a language they cannot read has to be able to
      // find their own way back.
      for (final locale in const [Locale('en'), Locale('de')]) {
        await pumpWithPreferences(
          tester,
          const AppPreferences(),
          locale: locale,
        );
        await scrollTo(tester, find.bySemanticsLabel('English'));
        expect(find.bySemanticsLabel('Deutsch'), findsOneWidget);
        expect(find.bySemanticsLabel('English'), findsOneWidget);
      }
    });

    testWidgets('marks the current choices as selected', (tester) async {
      await pumpWithPreferences(
        tester,
        const AppPreferences(
          appearance: AppearanceChoice.light,
          language: LanguageChoice.english,
        ),
      );
      await scrollTo(tester, find.bySemanticsLabel('English'));
      for (final (label, selected) in [
        ('Automatic', false),
        ('Light', true),
        ('Dark', false),
        ('Device language', false),
        ('English', true),
      ]) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isSelected: selected, isInMutuallyExclusiveGroup: true),
          reason: label,
        );
      }
    });

    testWidgets('explains what following the device means', (tester) async {
      await pumpWithPreferences(tester, const AppPreferences());
      await scrollTo(tester, find.textContaining('English otherwise'));
      expect(find.textContaining("device's light and dark"), findsOneWidget);
      expect(find.textContaining('English otherwise'), findsOneWidget);
    });
  });
}
