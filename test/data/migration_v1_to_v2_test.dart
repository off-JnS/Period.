// Only the two names this test builds rows with: drift also exports isNull
// and isNotNull as SQL expressions, which would shadow the matchers.
import 'package:drift/drift.dart' show RawValuesInsertable, Variable;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

/// The migration test CLAUDE.md section 5 requires, for schema 1 to 2.
///
/// Section 5 calls migrations the most dangerous part of this codebase, and it
/// is right: there is no cloud backup, so a migration that loses a row loses it
/// permanently. "Looks correct" is explicitly not good enough here, which is why
/// this builds a real version 1 database, fills it with the kind of data a real
/// user would have, runs the real migration, and reads every row back.
///
/// The version 1 schema is reconstructed from `drift_schemas/drift_schema_v1.json`,
/// which was committed while version 1 was current. That file is the reason this
/// test can exist at all -- without it there would be no way to build the old
/// schema except by checking out old code.
///
/// Regenerate the helpers this imports with:
///
///     dart run drift_dev schema generate drift_schemas/ test/data/generated/
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  // A user a few months in: several cycles recorded, days logged with varying
  // completeness, symptoms on some of them. Not a single tidy row -- the point
  // is to notice a migration that mangles the awkward cases.
  const march = '2024-03-04';
  const april = '2024-04-01';
  const may = '2024-04-29';

  Future<void> fillVersion1(v1.DatabaseAtV1 db) async {
    for (final date in [march, april, may]) {
      await db
          .into(db.periodStarts)
          .insert(RawValuesInsertable({'date': Variable(date)}));
    }

    await db
        .into(db.dayEntries)
        .insert(
          RawValuesInsertable({
            'date': Variable(march),
            'flow': Variable('heavy'),
            'note': Variable('Worse than last month'),
          }),
        );
    // Flow recorded, no note. Section 5: null means not recorded, and a
    // migration that turned it into an empty string would be losing that.
    await db
        .into(db.dayEntries)
        .insert(
          RawValuesInsertable({
            'date': Variable(april),
            'flow': Variable('light'),
          }),
        );
    // A note and nothing else.
    await db
        .into(db.dayEntries)
        .insert(
          RawValuesInsertable({
            'date': Variable('2024-04-15'),
            'note': Variable("Didn't sleep"),
          }),
        );

    for (final symptom in ['cramps', 'headache']) {
      await db
          .into(db.daySymptoms)
          .insert(
            RawValuesInsertable({
              'date': Variable(march),
              'symptom_key': Variable(symptom),
            }),
          );
    }
    // A symptom on a day with no entry row at all, which LogDao.entryOn treats
    // as a logged day. Easy to lose and easy not to notice.
    await db
        .into(db.daySymptoms)
        .insert(
          RawValuesInsertable({
            'date': Variable('2024-04-20'),
            'symptom_key': Variable('tiredness'),
          }),
        );
  }

  test('the schema matches what drift expects at version 2', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 2);
  });

  group('a version 1 database with real data in it', () {
    late AppDatabase migrated;

    setUp(() async {
      final schema = await verifier.schemaAt(1);

      final old = v1.DatabaseAtV1(schema.newConnection());
      await fillVersion1(old);
      await old.close();

      migrated = AppDatabase(schema.newConnection());
      addTearDown(migrated.close);
      await verifier.migrateAndValidate(migrated, 2);
    });

    test('keeps every period start', () async {
      expect(await migrated.logDao.allPeriodStarts(), [
        CycleDate.parseIso8601(march),
        CycleDate.parseIso8601(april),
        CycleDate.parseIso8601(may),
      ]);
    });

    test('keeps a fully filled entry', () async {
      final entry = await migrated.logDao.entryOn(
        CycleDate.parseIso8601(march),
      );
      expect(entry, isNotNull);
      expect(entry!.flow, FlowIntensity.heavy);
      expect(entry.note, 'Worse than last month');
      expect(entry.symptoms, {
        const Symptom(key: 'cramps'),
        const Symptom(key: 'headache'),
      });
    });

    test('keeps null meaning "not recorded" rather than empty', () async {
      final entry = await migrated.logDao.entryOn(
        CycleDate.parseIso8601(april),
      );
      expect(entry!.flow, FlowIntensity.light);
      expect(entry.note, isNull);
      expect(entry.symptoms, isEmpty);
    });

    test('keeps an entry that is only a note', () async {
      final entry = await migrated.logDao.entryOn(aprilFifteenth);
      expect(entry!.note, "Didn't sleep");
      expect(entry.flow, isNull);
    });

    test('keeps a symptom logged on a day with no entry row', () async {
      final entry = await migrated.logDao.entryOn(aprilTwentieth);
      expect(entry, isNotNull);
      expect(entry!.symptoms, {const Symptom(key: 'tiredness')});
    });

    test('adds the settings table, empty', () async {
      final stored = await migrated.settingsDao.readSettings();
      expect(stored.cycle.mode.name, 'natural');
      expect(stored.cycle.predictionsOptedIn, isFalse);
      expect(stored.fertileWindowOptedIn, isFalse);
    });

    test('and the settings table is writable afterwards', () async {
      await migrated.settingsDao.writeFertileWindowOptIn(optedIn: true);
      final stored = await migrated.settingsDao.readSettings();
      expect(stored.fertileWindowOptedIn, isTrue);
    });
  });
}

final aprilFifteenth = CycleDate.parseIso8601('2024-04-15');
final aprilTwentieth = CycleDate.parseIso8601('2024-04-20');
