import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/profile/cycle_mode_section.dart';

import '../support/widgets.dart';

/// The mode list and its switches, which live on Profile.
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
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CycleModeSection(settings: settings, onChanged: changes.add),
          ],
        ),
      ),
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

    testWidgets('turning it on asks first, stating the caveat', (tester) async {
      final changes = await pumpScreen(tester, const CycleSettings());
      await tester.tap(find.text('Estimated fertile window'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CupertinoAlertDialog),
          matching: find.textContaining(
            'Not suitable for preventing pregnancy',
          ),
        ),
        findsOneWidget,
      );
      expect(changes, isEmpty);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(changes, [const CycleSettings(fertileWindowOptedIn: true)]);
    });

    testWidgets('Cancel leaves it off', (tester) async {
      final changes = await pumpScreen(tester, const CycleSettings());
      await tester.tap(find.text('Estimated fertile window'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('turning it off needs no dialog', (tester) async {
      final changes = await pumpScreen(
        tester,
        const CycleSettings(fertileWindowOptedIn: true),
      );
      await tester.tap(find.text('Estimated fertile window'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(changes, [const CycleSettings()]);
    });
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
}
