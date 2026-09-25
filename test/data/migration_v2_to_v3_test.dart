import 'package:drift_dev/api/migrations_native.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../generated_migrations/schema.dart';
import '../support/dates.dart';
import '../support/models.dart';

/// Section 5: v2 -> v3 adds the temperature column. Built from drift's
/// snapshot of v2, filled with realistic data, migrated, and checked.
void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  final starts = [aDate(2024, 3, 4), aDate(2024, 3, 25), aDate(2024, 5, 4)];
  final entries = [
    aDayEntry(
      date: aDate(2024, 5, 4),
      flow: FlowIntensity.heavy,
      note: 'Krämpfe am Morgen — besser nach dem Tee ☕️',
      symptoms: {
        aSymptom(key: 'cramps'),
        aSymptom(key: 'mood.sad'),
      },
    ),
    aDayEntry(date: aDate(2024, 3, 25), flow: FlowIntensity.light),
    aDayEntry(date: aDate(2024, 4, 10), note: 'only a note'),
  ];

  void fillVersion2(InitializedSchema schema) {
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
    for (final (key, value) in [
      ('cycle_mode', 'perimenopause'),
      ('predictions_opted_in', 'true'),
      ('app_lock', 'true'),
      ('reminder_time', '20:30'),
    ]) {
      raw.execute(
        'INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?)',
        [key, value],
      );
    }
  }

  test('the migrated schema equals a fresh version 3 schema', () async {
    final db = AppDatabase(await verifier.startAt(2));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);
  });

  test('every version 2 row survives byte for byte', () async {
    final schema = await verifier.schemaAt(2);
    fillVersion2(schema);
    const dumps = {
      'period_starts': 'SELECT * FROM period_starts ORDER BY date',
      'day_symptoms': 'SELECT * FROM day_symptoms ORDER BY date, symptom_key',
      'app_settings': 'SELECT * FROM app_settings ORDER BY setting_key',
      'day_entries': 'SELECT date, flow, note FROM day_entries ORDER BY date',
    };
    final before = {
      for (final MapEntry(:key, :value) in dumps.entries)
        key: schema.rawDatabase.select(value).map((row) => {...row}).toList(),
    };

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);

    for (final MapEntry(:key, :value) in dumps.entries) {
      final after = await db.customSelect(value).get();
      expect(after.map((row) => row.data).toList(), before[key], reason: key);
    }
  });

  test('old entries read back unchanged, with no temperature', () async {
    final schema = await verifier.schemaAt(2);
    fillVersion2(schema);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);

    for (final entry in entries) {
      final read = await db.logDao.entryOn(entry.date);
      expect(read, entry);
      expect(read!.temperatureCentiCelsius, isNull);
    }
    expect(await db.logDao.allPeriodStarts(), starts);
  });

  test('her settings survive the migration', () async {
    final schema = await verifier.schemaAt(2);
    fillVersion2(schema);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);

    expect(
      await db.settingsDao.cycleSettings(),
      const CycleSettings(
        mode: CycleMode.perimenopause,
        predictionsOptedIn: true,
      ),
    );
    expect(await db.settingsDao.appLockEnabled(), isTrue);
    final reminders = await db.settingsDao.reminderSettings();
    expect((reminders.hour, reminders.minute), (20, 30));
  });

  test('a temperature can be saved straight after migrating', () async {
    final schema = await verifier.schemaAt(2);
    fillVersion2(schema);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 3);

    final withTemperature = aDayEntry(date: aDate(2024, 5, 10))
        .copyWith(temperatureCentiCelsius: 3645);
    await db.logDao.saveEntry(withTemperature);
    expect(await db.logDao.entryOn(aDate(2024, 5, 10)), withTemperature);
  });
}
