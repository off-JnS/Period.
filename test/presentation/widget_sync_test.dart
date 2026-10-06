import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/l10n/app_localizations.dart';
import 'package:period/presentation/widget/widget_sync.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fake_widget_bridge.dart';
import '../support/fixed_clock.dart';

void main() {
  setUpAll(initializeDateFormatting);

  late AppDatabase database;
  late FakeWidgetBridge bridge;
  late AppLocalizations l10n;
  var locked = false;
  final today = aDate(2024, 5, 17);

  setUp(() async {
    database = aDatabase();
    bridge = FakeWidgetBridge();
    locked = false;
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    for (final start in regularPeriodStarts(
      from: aDate(2024, 2, 9),
      length: 28,
      count: 4,
    )) {
      await database.logDao.addPeriodStart(start);
    }
  });
  tearDown(() => database.close());

  WidgetSync sync() => WidgetSync(
    logDao: database.logDao,
    settingsDao: database.settingsDao,
    bridge: bridge,
    clock: FixedClock(today),
    lockEnabled: () => locked,
  );

  Future<Map<String, Object?>> snapshot() =>
      sync().buildSnapshot(l10n: l10n, locale: 'en');

  test('has exactly the fields the Swift widget decodes', () async {
    // ios/PeriodWidget/PeriodWidget.swift, struct Snapshot. A field renamed
    // on one side only would silently blank the widget.
    expect((await snapshot()).keys.toSet(), {
      'locked',
      'detailed',
      'mode',
      'lastStart',
      'typicalLength',
      'dayLabel',
      'pregnancyLabel',
      'detailLine',
    });
  });

  test('gives the last start, and labels with placeholders to fill', () async {
    final s = await snapshot();
    expect(s['lastStart'], '2024-05-03');
    expect(s['dayLabel'], 'Day {day}');
    expect(s['pregnancyLabel'], '{weeks}+{days}');
    expect(s['typicalLength'], 28);
    expect(s['locked'], false);
  });

  test('discreet by default: no estimate text', () async {
    final s = await snapshot();
    expect(s['detailed'], false);
    expect(s['detailLine'], isNull);
  });

  test('detailed: adds the estimate as text', () async {
    await database.settingsDao.saveWidgetDetailed(detailed: true);
    final s = await snapshot();
    expect(s['detailed'], true);
    expect(s['detailLine'], startsWith('Next period '));
  });

  test('with the lock on, not even the start date leaves the app', () async {
    await database.settingsDao.saveWidgetDetailed(detailed: true);
    locked = true;
    final s = await snapshot();
    expect(s['locked'], true);
    expect(s['lastStart'], isNull);
    expect(s['detailLine'], isNull);
    expect(s['typicalLength'], isNull);
  });

  test('pregnancy: says so, and gives no cycle length', () async {
    await database.settingsDao.saveCycleSettings(
      const CycleSettings(mode: CycleMode.pregnancy),
    );
    final s = await snapshot();
    expect(s['mode'], 'pregnancy');
    expect(s['typicalLength'], isNull);
  });

  test('a start after today is not used', () async {
    await database.logDao.addPeriodStart(today.addDays(3));
    expect((await snapshot())['lastStart'], '2024-05-03');
  });

  test('sync hands the snapshot to the bridge', () async {
    await sync().sync(l10n, 'en');
    expect(bridge.snapshots.single['lastStart'], '2024-05-03');
  });

  test('labels follow the app language', () async {
    final de = await AppLocalizations.delegate.load(const Locale('de'));
    final s = await sync().buildSnapshot(l10n: de, locale: 'de');
    expect(s['dayLabel'], 'Tag {day}');
  });
}
