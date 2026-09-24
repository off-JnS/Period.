import 'package:drift_dev/api/migrations_native.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../generated_migrations/schema.dart';
import '../support/dates.dart';
import '../support/models.dart';

/// Section 5: every migration needs a test that builds the previous schema,
/// fills it with realistic data, migrates, and asserts the data survived.
///
/// The version 1 database here is built from the schema snapshot drift took of
/// version 1 (`drift_schemas/drift_schema_v1.json`), not from today's table
/// definitions, so it is the file a real user's phone holds.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  /// A history with the awkward cases section 7 lists: irregular gaps, a
  /// three-month gap, entries logged out of order, a day with symptoms but no
  /// entry row, a note with non-ASCII text, and every flow value.
  final starts = [
    aDate(2023, 11, 2),
    aDate(2023, 11, 30),
    aDate(2024, 3, 4), // three-month gap
    aDate(2024, 3, 25), // 21-day cycle
    aDate(2024, 5, 4), // 40-day cycle
    aDate(2024, 6, 1),
  ];
  final entries = [
    aDayEntry(
      date: aDate(2024, 6, 2),
      flow: FlowIntensity.heavy,
      note: 'Krämpfe am Morgen — besser nach dem Tee ☕️',
      symptoms: {
        aSymptom(key: 'cramps'),
        aSymptom(key: 'headache'),
      },
    ),
    aDayEntry(date: aDate(2023, 11, 2), flow: FlowIntensity.light),
    aDayEntry(date: aDate(2024, 3, 25), flow: FlowIntensity.medium),
    aDayEntry(date: aDate(2024, 5, 5), flow: FlowIntensity.light),
    aDayEntry(date: aDate(2024, 5, 20), flow: FlowIntensity.none),
    aDayEntry(date: aDate(2024, 4, 10), note: 'only a note'),
  ];
  // Symptoms with no entry row on that day: a logged day all the same.
  final symptomOnlyDay = aDate(2024, 4, 18);

  void fillVersion1(InitializedSchema schema) {
    final raw = schema.rawDatabase;
    for (final start in starts) {
      raw.execute('INSERT INTO period_starts (date) VALUES (?)', [
        start.toIso8601(),
      ]);
    }
    for (final entry in entries) {
      raw.execute(
        'INSERT INTO day_entries (date, flow, note) VALUES (?, ?, ?)',
        [entry.date.toIso8601(), entry.flow?.name, entry.note],
      );
      for (final symptom in entry.symptoms) {
        raw.execute(
          'INSERT INTO day_symptoms (date, symptom_key) VALUES (?, ?)',
          [entry.date.toIso8601(), symptom.key],
        );
      }
    }
    raw.execute('INSERT INTO day_symptoms (date, symptom_key) VALUES (?, ?)', [
      symptomOnlyDay.toIso8601(),
      'bloating',
    ]);
  }

  /// Every row of every version 1 table, in a fixed order.
  const dumps = {
    'period_starts': 'SELECT * FROM period_starts ORDER BY date',
    'day_entries': 'SELECT * FROM day_entries ORDER BY date',
    'day_symptoms': 'SELECT * FROM day_symptoms ORDER BY date, symptom_key',
  };

  test('the schema after migrating equals a fresh version 2 schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 2);
  });

  test('every version 1 row survives byte for byte', () async {
    final schema = await verifier.schemaAt(1);
    fillVersion1(schema);

    final before = {
      for (final MapEntry(:key, :value) in dumps.entries)
        key: schema.rawDatabase.select(value).map((row) => {...row}).toList(),
    };
    expect(before['period_starts'], hasLength(starts.length));

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);

    for (final MapEntry(:key, :value) in dumps.entries) {
      final after = await db.customSelect(value).get();
      expect(
        after.map((row) => row.data).toList(),
        before[key],
        reason: '$key changed during the migration',
      );
    }
  });

  test(
    'the migrated data reads back through the app as it was logged',
    () async {
      final schema = await verifier.schemaAt(1);
      fillVersion1(schema);

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);

      expect(await db.logDao.allPeriodStarts(), starts);
      for (final entry in entries) {
        expect(await db.logDao.entryOn(entry.date), entry);
      }
      final symptomOnly = await db.logDao.entryOn(symptomOnlyDay);
      expect(symptomOnly?.symptoms.map((symptom) => symptom.key), ['bloating']);
    },
  );

  test(
    'a migrated user starts with the defaults version 1 behaved as',
    () async {
      final schema = await verifier.schemaAt(1);
      fillVersion1(schema);

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);

      // Version 1 had no settings and treated everyone as a natural cycle with
      // the fertile window off. Migrating must not change what she sees.
      expect(await db.settingsDao.cycleSettings(), const CycleSettings());
    },
  );

  test('settings can be saved straight after migrating', () async {
    final schema = await verifier.schemaAt(1);
    fillVersion1(schema);

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);

    const chosen = CycleSettings(mode: CycleMode.pregnancy);
    await db.settingsDao.saveCycleSettings(chosen);
    expect(await db.settingsDao.cycleSettings(), chosen);
    // And saving did not disturb anything she had logged.
    expect(await db.logDao.allPeriodStarts(), starts);
  });

  test('a history with no rows at all migrates too', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 2);
    expect(await db.logDao.allPeriodStarts(), isEmpty);
  });
}
