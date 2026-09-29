import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/settings/reminders_screen.dart';

import '../support/dates.dart';
import '../support/widgets.dart';

/// The reminders page, opened from Settings. docs/cycle-logic.md §8.
void main() {
  final today = aDate(2024, 5, 17);

  Future<List<ReminderSettings>> pump(
    WidgetTester tester,
    ReminderSettings reminders, {
    ContraceptionMethod? method,
    bool blocked = false,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    final changes = <ReminderSettings>[];
    await pumpApp(
      tester,
      RemindersScreen(
        reminders: reminders,
        method: method,
        today: today,
        blocked: blocked,
        onChanged: changes.add,
      ),
      locale: locale,
      textScale: textScale,
      surface: const Size(400, 1600),
    );
    return changes;
  }

  group('the cycle', () {
    testWidgets('turning one on reports it', (tester) async {
      final changes = await pump(tester, const ReminderSettings());
      await tester.tap(find.text('Before my period'));
      await tester.pump();
      expect(changes, [const ReminderSettings(periodComing: true)]);
    });

    testWidgets('lead time and time appear only once they matter', (
      tester,
    ) async {
      await pump(tester, const ReminderSettings());
      expect(find.text('Days before'), findsNothing);
      expect(find.text('Time'), findsNothing);

      await pump(tester, const ReminderSettings(dailyLog: true));
      expect(find.text('Days before'), findsNothing);
      expect(find.text('Time'), findsOneWidget);

      await pump(tester, const ReminderSettings(periodComing: true));
      expect(find.text('Days before'), findsOneWidget);
    });

    testWidgets('choosing a lead time reports it', (tester) async {
      final changes = await pump(
        tester,
        const ReminderSettings(periodComing: true),
      );
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      expect(changes.last.daysBefore, 4);
    });

    testWidgets('shows the time in the device format', (tester) async {
      await pump(
        tester,
        const ReminderSettings(dailyLog: true, hour: 21, minute: 30),
      );
      expect(find.text('9:30 PM'), findsOneWidget);
    });

    testWidgets('says how to fix refused notifications', (tester) async {
      await pump(tester, const ReminderSettings(), blocked: true);
      expect(find.textContaining("phone's settings"), findsOneWidget);
    });
  });

  group('contraception', () {
    testWidgets('without a method, points to Profile', (tester) async {
      await pump(tester, const ReminderSettings());
      expect(
        find.textContaining('Choose your contraception in Profile'),
        findsOne,
      );
      expect(find.byKey(RemindersKeys.methodSwitch), findsNothing);
    });

    testWidgets('a method with nothing to remind of says so', (tester) async {
      await pump(
        tester,
        const ReminderSettings(),
        method: ContraceptionMethod.condom,
      );
      expect(find.textContaining('nothing to be reminded of'), findsOneWidget);
      expect(find.byKey(RemindersKeys.methodSwitch), findsNothing);
    });

    testWidgets('shows the reminder for her method, off until turned on', (
      tester,
    ) async {
      final changes = await pump(
        tester,
        const ReminderSettings(),
        method: ContraceptionMethod.combinedPill,
      );
      expect(find.text('Contraception: Combined pill'), findsOneWidget);
      expect(find.text('Pack'), findsNothing);

      await tester.tap(find.byKey(RemindersKeys.methodSwitch));
      await tester.pump();
      expect(changes.single.pill, isTrue);
    });

    testWidgets('a pack with a break asks for its first day, today to start', (
      tester,
    ) async {
      final changes = await pump(
        tester,
        const ReminderSettings(pill: true),
        method: ContraceptionMethod.combinedPill,
      );
      expect(find.text('First day of this pack'), findsNothing);
      await tester.tap(find.text('21 + 7 break'));
      await tester.pumpAndSettle();
      expect(changes.last.pillPack, PillPack.days21);
      expect(changes.last.pillPackStart, today);

      await pump(
        tester,
        changes.last,
        method: ContraceptionMethod.combinedPill,
      );
      expect(find.text('First day of this pack'), findsOneWidget);
    });

    testWidgets('a date is kept only when Done is tapped', (tester) async {
      final changes = await pump(
        tester,
        const ReminderSettings(ring: true),
        method: ContraceptionMethod.ring,
      );
      expect(find.text('Not set'), findsOneWidget);

      final open = find.descendant(
        of: find.byKey(RemindersKeys.methodDate),
        matching: find.byType(CupertinoButton),
      );
      // Dismissed without Done: nothing changes.
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);

      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(RemindersKeys.dateWheel),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final picked = changes.single.ringInserted;
      expect(picked, isNotNull);
      expect(picked!.isAfter(today), isFalse);
    });

    testWidgets('the injection interval steps a week at a time', (
      tester,
    ) async {
      final changes = await pump(
        tester,
        const ReminderSettings(injection: true, injectionWeeks: 14),
        method: ContraceptionMethod.injection,
      );
      expect(find.text('14 weeks'), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.plus_circle));
      await tester.tap(find.byIcon(CupertinoIcons.minus_circle));
      await tester.pump();
      // Already at the most, so only the step down is reported.
      expect(changes.single.injectionWeeks, 13);
    });

    testWidgets('an IUD asks for its date and how far ahead to remind', (
      tester,
    ) async {
      final changes = await pump(
        tester,
        const ReminderSettings(device: true),
        method: ContraceptionMethod.copperIud,
      );
      expect(find.text('Replace by'), findsOneWidget);
      await tester.tap(find.text('8 wk'));
      await tester.pumpAndSettle();
      expect(changes.single.deviceWeeksBefore, 8);
    });

    testWidgets('lists what is coming up, in words, only in the app', (
      tester,
    ) async {
      await pump(
        tester,
        ReminderSettings(ring: true, ringInserted: today),
        method: ContraceptionMethod.ring,
      );
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text('Take out the ring'), findsWidgets);
      expect(find.text('Put in a new ring'), findsWidgets);
      expect(find.textContaining('only says'), findsOneWidget);
    });

    testWidgets('a reminder for another method is not shown', (tester) async {
      await pump(
        tester,
        const ReminderSettings(pill: true),
        method: ContraceptionMethod.patch,
      );
      expect(find.text('Take your pill'), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(RemindersKeys.methodSwitch))
            .value,
        isFalse,
      );
    });

    testWidgets('German, and the largest text, fit', (tester) async {
      await pump(
        tester,
        const ReminderSettings(pill: true, pillPack: PillPack.days24),
        method: ContraceptionMethod.progestinPill,
        locale: const Locale('de'),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Pille'), findsOneWidget);
    });
  });
}
