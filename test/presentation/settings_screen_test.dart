import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/widgets.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) => pumpApp(
    tester,
    const SettingsScreen(),
    locale: locale,
    textScale: textScale,
  );

  testWidgets('restates that settings stay encrypted on the device', (
    tester,
  ) async {
    await pumpScreen(tester);
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
    await pumpScreen(tester, locale: const Locale('de'), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Einstellungen'), findsWidgets);
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

  group('reminders', () {
    testWidgets('are left out without reminder settings', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Reminders'), findsNothing);
    });

    testWidgets('are a row that opens their own page, saying if any is on', (
      tester,
    ) async {
      var opened = 0;
      await pumpApp(
        tester,
        SettingsScreen(
          reminders: const ReminderSettings(pill: true),
          onOpenReminders: () => opened++,
        ),
      );
      expect(find.text('On'), findsOneWidget);
      await tester.tap(find.byKey(SettingsKeys.reminders));
      expect(opened, 1);

      await pumpApp(
        tester,
        const SettingsScreen(reminders: ReminderSettings()),
      );
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('says the notification text is neutral', (tester) async {
      await pumpApp(
        tester,
        const SettingsScreen(reminders: ReminderSettings()),
      );
      expect(find.textContaining('only ever say'), findsOneWidget);
    });

    testWidgets('says how to fix refused notifications', (tester) async {
      await pumpApp(
        tester,
        const SettingsScreen(
          reminders: ReminderSettings(),
          remindersBlocked: true,
        ),
      );
      expect(find.textContaining("phone's settings"), findsOneWidget);
    });
  });
}
