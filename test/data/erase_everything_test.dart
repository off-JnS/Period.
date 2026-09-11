import 'dart:io';

import 'package:drift/native.dart';
import 'package:period/data/database/database.dart';
import 'package:period/data/erase_everything.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

/// CLAUDE.md section 9: "Delete all data" must actually delete.
///
/// Dropping the rows was all it did, and that left her dates in two places: the
/// `<db>.backup-v<n>` copies section 5 writes beside the database, and the
/// freed pages inside the database itself, which deleting a row marks reusable
/// rather than overwriting.
///
/// These use a plain file-backed database, not an encrypted one, so the traces
/// are directly readable and the assertions can be blunt. On the shipped app
/// those bytes are ciphertext -- but the key that reads them stays in the
/// keystore, so "still in the file" still means "not deleted".
void main() {
  late Directory documents;
  late File dbFile;
  late AppDatabase db;

  const herDate = '2024-05-17';

  setUp(() {
    documents = Directory.systemTemp.createTempSync('period_erase_test');
    dbFile = File('${documents.path}/$databaseFileName');
    db = AppDatabase(NativeDatabase(dbFile));
  });

  tearDown(() async {
    await db.close();
    documents.deleteSync(recursive: true);
  });

  Future<void> logSomething() async {
    await db.logDao.addPeriodStart(CycleDate(2024, 5, 17));
    await db.logDao.saveEntry(
      DayEntry(
        date: CycleDate(2024, 5, 17),
        flow: FlowIntensity.medium,
        symptoms: const {},
      ),
    );
    await db.customStatement('PRAGMA wal_checkpoint(FULL);');
  }

  File writeMigrationBackup() => dbFile.copySync('${dbFile.path}.backup-v1');

  bool fileStillHolds(File file, String text) =>
      String.fromCharCodes(file.readAsBytesSync()).contains(text);

  test('the tables are empty afterwards', () async {
    await logSomething();

    await eraseEverything(db, documents: documents);

    expect(await db.logDao.allPeriodStarts(), isEmpty);
    expect(await db.logDao.allEntries(), isEmpty);
  });

  test('the migration copies are gone', () async {
    await logSomething();
    final backup = writeMigrationBackup();
    expect(
      fileStillHolds(backup, herDate),
      isTrue,
      reason: 'the copy has to contain her data for this test to mean anything',
    );

    await eraseEverything(db, documents: documents);

    expect(
      backup.existsSync(),
      isFalse,
      reason:
          'a file of her entries beside the database is not a fresh install',
    );
  });

  test('every copy goes, not just the newest', () async {
    // A phone that has been through two migrations has two of them, and the
    // erase does not know which versions this one has seen.
    await logSomething();
    final first = dbFile.copySync('${dbFile.path}.backup-v1');
    final second = dbFile.copySync('${dbFile.path}.backup-v2');

    await eraseEverything(db, documents: documents);

    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isFalse);
    expect(migrationBackupsIn(documents), isEmpty);
  });

  test('her data is not left in the freed pages', () async {
    await logSomething();
    expect(
      fileStillHolds(dbFile, herDate),
      isTrue,
      reason: 'she logged it, so it should be in the file to begin with',
    );

    await eraseEverything(db, documents: documents);

    expect(
      fileStillHolds(dbFile, herDate),
      isFalse,
      reason:
          'deleting rows only marks pages reusable; without VACUUM her dates '
          'stay in the file until something else happens to need the space',
    );
  });

  test('it leaves other files in the directory alone', () async {
    // The erase deletes by prefix, and the documents directory is not
    // necessarily ours alone.
    await logSomething();
    final unrelated = File('${documents.path}/something-else.txt')
      ..writeAsStringSync('not ours');

    await eraseEverything(db, documents: documents);

    expect(unrelated.existsSync(), isTrue);
    expect(dbFile.existsSync(), isTrue, reason: 'the database is still in use');
  });

  test('it copes with a directory that is not there', () async {
    await logSomething();
    final missing = Directory('${documents.path}/gone');

    await expectLater(eraseEverything(db, documents: missing), completes);
    expect(await db.logDao.allPeriodStarts(), isEmpty);
  });
}
