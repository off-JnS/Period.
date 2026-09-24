import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/presentation/today/today_page.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// Covers the page that connects the Today screen to the database.
///
/// These go through the real DAO against an in-memory database rather than a
/// mock, because what is being checked is that logging a day actually changes
/// what the next read computes -- section 4's whole design. A mocked DAO would
/// assert that a method was called and prove nothing about that.
void main() {
  late AppDatabase database;
  final today = aDate(2024, 5, 17);

  setUp(() => database = aDatabase());
  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester, {Locale? locale}) async {
    await pumpApp(
      tester,
      TodayPage(
        logDao: database.logDao,
        settingsDao: database.settingsDao,
        clock: FixedClock(today),
      ),
      locale: locale ?? const Locale('en'),
    );
  }

  group('a fresh install', () {
    testWidgets('says nothing is logged rather than showing an empty card', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.text('Nothing logged today'), findsOneWidget);
      expect(find.text('No cycle yet'), findsOneWidget);
    });

    testWidgets('offers a labelled way to add an entry', (tester) async {
      await pumpPage(tester);
      expect(find.widgetWithText(FilledButton, 'Add entry'), findsOne);
    });
  });

  group('what is already stored', () {
    testWidgets('is summarised for today', (tester) async {
      await database.logDao.saveEntry(
        aDayEntry(
          date: today,
          flow: FlowIntensity.light,
          note: 'a quiet day',
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );
      await database.logDao.addPeriodStart(today);

      await pumpPage(tester);

      expect(find.text('Period started today'), findsOneWidget);
      expect(find.text('Flow: Light'), findsOneWidget);
      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('a quiet day'), findsOneWidget);
    });

    testWidgets('counts the cycle day from the last recorded start', (
      tester,
    ) async {
      await database.logDao.addPeriodStart(today.subtractDays(4));
      await pumpPage(tester);

      // The start itself is day 1, so four days later is day 5.
      expect(find.bySemanticsLabel('Cycle day 5'), findsOneWidget);
    });

    testWidgets('shows a period start with no entry on it', (tester) async {
      // A day can be marked as a start and hold nothing else. The summary has
      // to say so rather than reading as an empty day.
      await database.logDao.addPeriodStart(today);
      await pumpPage(tester);

      expect(find.text('Period started today'), findsOneWidget);
      expect(find.text('Nothing logged today'), findsNothing);
    });

    testWidgets('estimates a window once there are enough cycles', (
      tester,
    ) async {
      for (final start in regularPeriodStarts(
        from: today.subtractDays(84),
        length: 28,
        count: 4,
      )) {
        await database.logDao.addPeriodStart(start);
      }

      await pumpPage(tester);

      // Section 8: an estimate is always a range, and always qualified.
      expect(find.textContaining('–'), findsWidgets);
      expect(find.text('Estimated, based on your entries'), findsOneWidget);
    });
  });

  group('logging through the screen', () {
    testWidgets('writes a period start and recomputes the cycle day', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(find.text('No cycle yet'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await database.logDao.allPeriodStarts(), [today]);
      // Recomputed on read, not stored: the start is day 1.
      expect(find.bySemanticsLabel('Cycle day 1'), findsOneWidget);
      expect(find.text('Period started today'), findsOneWidget);
    });

    testWidgets('writes flow, symptoms and a note', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Headache'));
      await tester.pumpAndSettle();
      // The note is the last section and sits below the fold.
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'long day');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await database.logDao.entryOn(today);
      expect(stored?.flow, FlowIntensity.heavy);
      expect(stored?.note, 'long day');
      expect(stored?.symptoms, contains(aSymptom(key: 'headache')));
    });

    testWidgets('unmarking a period start removes it', (tester) async {
      // The correction path. Section 4 rests on this being cheap and on nothing
      // derived surviving it.
      await database.logDao.addPeriodStart(today);
      await pumpPage(tester);
      expect(find.bySemanticsLabel('Cycle day 1'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await database.logDao.allPeriodStarts(), isEmpty);
      expect(find.text('No cycle yet'), findsOneWidget);
    });

    testWidgets('deleting clears the entry and the period start', (
      tester,
    ) async {
      // Section 9 requires deletion to actually delete, and the confirmation
      // text promises the start goes with it.
      await database.logDao.saveEntry(
        aDayEntry(date: today, flow: FlowIntensity.medium),
      );
      await database.logDao.addPeriodStart(today);
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete entry'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await database.logDao.entryOn(today), isNull);
      expect(await database.logDao.allPeriodStarts(), isEmpty);
      expect(find.text('Nothing logged today'), findsOneWidget);
    });

    testWidgets('backing out without saving changes nothing', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Heavy'));
      await tester.pumpAndSettle();
      // The sheet's Cancel, which is what backing out is on iOS. Something
      // was changed, so it asks first.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();

      expect(await database.logDao.entryOn(today), isNull);
      expect(find.text('Nothing logged today'), findsOneWidget);
    });
  });

  group('German', () {
    testWidgets('renders the summary without an English string', (
      tester,
    ) async {
      await database.logDao.addPeriodStart(today);
      await pumpPage(tester, locale: const Locale('de'));

      expect(find.text('Heute eingetragen'), findsOneWidget);
      expect(find.text('Periode hat heute begonnen'), findsOneWidget);
      expect(find.text('Eintrag hinzufügen'), findsOneWidget);
    });
  });

  group('the stored settings', () {
    Future<void> logRegularHistory() async {
      for (final start in regularPeriodStarts(
        from: today.subtractDays(84),
        length: 28,
        count: 4,
      )) {
        await database.logDao.addPeriodStart(start);
      }
    }

    testWidgets('pregnancy turns the estimate off and says why', (
      tester,
    ) async {
      await logRegularHistory();
      await database.settingsDao.saveCycleSettings(
        const CycleSettings(mode: CycleMode.pregnancy),
      );
      await pumpPage(tester);

      expect(
        find.textContaining('Estimates are off during pregnancy'),
        findsOne,
      );
      expect(find.text('Estimated, based on your entries'), findsNothing);
    });

    testWidgets('pregnancy hides the usual length but keeps the day', (
      tester,
    ) async {
      await logRegularHistory();
      await database.settingsDao.saveCycleSettings(
        const CycleSettings(mode: CycleMode.pregnancy),
      );
      await pumpPage(tester);

      expect(find.bySemanticsLabel('Cycle day 1'), findsOneWidget);
      expect(find.textContaining('usually'), findsNothing);
    });

    testWidgets('hormonal contraception turns the estimate off and says why', (
      tester,
    ) async {
      await logRegularHistory();
      await database.settingsDao.saveCycleSettings(
        const CycleSettings(mode: CycleMode.hormonalContraception),
      );
      await pumpPage(tester);

      expect(find.textContaining('follows your regimen'), findsOne);
      expect(find.text('Estimated, based on your entries'), findsNothing);
    });

    testWidgets('the fertile window appears only once opted in', (
      tester,
    ) async {
      await logRegularHistory();
      await pumpPage(tester);
      expect(find.text('Estimated fertile window'), findsNothing);

      await database.settingsDao.saveCycleSettings(
        const CycleSettings(fertileWindowOptedIn: true),
      );
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester);
      await tester.scrollUntilVisible(
        find.text('Estimated fertile window'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Estimated fertile window'), findsOneWidget);
      expect(
        find.textContaining('Not suitable for preventing pregnancy'),
        findsOneWidget,
      );
    });

    testWidgets('an opted-in fertile window stays hidden without an estimate', (
      tester,
    ) async {
      await logRegularHistory();
      await database.settingsDao.saveCycleSettings(
        const CycleSettings(
          mode: CycleMode.perimenopause,
          fertileWindowOptedIn: true,
        ),
      );
      await pumpPage(tester);
      expect(find.text('Estimated fertile window'), findsNothing);
    });
  });
}
