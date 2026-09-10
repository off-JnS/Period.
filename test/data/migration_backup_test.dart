import 'dart:io';

import 'package:period/data/database/database.dart';
import 'package:period/data/database/encryption.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Section 5 requires the database to be copied to `<db>.backup-v<n>` before any
/// migration runs, because there is no cloud backup and a broken migration
/// destroys a user's data with no recovery path.
///
/// There is no migration yet -- schema 1 is the first. These tests pin the
/// behaviour now, while there is nothing to lose, so that the first real
/// migration inherits a copy step that has already been proven rather than one
/// written under pressure.
void main() {
  late Directory dir;
  late File dbFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('period_backup_test');
    dbFile = File('${dir.path}/period.sqlite');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  int stubVersion(int version) => version;

  test('copies the file when the schema is behind', () async {
    dbFile.writeAsStringSync('the user data');

    final backup = await backUpBeforeMigration(
      dbFile,
      2,
      readSchemaVersion: (_) => stubVersion(1),
    );

    expect(backup, isNotNull);
    expect(backup!.path, '${dbFile.path}.backup-v1');
    expect(backup.readAsStringSync(), 'the user data');
  });

  test('leaves the original untouched', () async {
    dbFile.writeAsStringSync('the user data');

    await backUpBeforeMigration(
      dbFile,
      2,
      readSchemaVersion: (_) => stubVersion(1),
    );

    expect(dbFile.readAsStringSync(), 'the user data');
  });

  test('names the backup after the version being left behind', () async {
    dbFile.writeAsStringSync('x');

    final backup = await backUpBeforeMigration(
      dbFile,
      7,
      readSchemaVersion: (_) => stubVersion(4),
    );

    expect(backup!.path, endsWith('.backup-v4'));
  });

  test('does nothing when there is no database yet', () async {
    final backup = await backUpBeforeMigration(
      dbFile,
      2,
      readSchemaVersion: (_) => stubVersion(1),
    );

    expect(backup, isNull);
  });

  test('does nothing for a fresh file drift has not written yet', () async {
    dbFile.writeAsStringSync('');

    final backup = await backUpBeforeMigration(
      dbFile,
      1,
      readSchemaVersion: (_) => stubVersion(0),
    );

    expect(backup, isNull);
  });

  test('does nothing when already at the target version', () async {
    dbFile.writeAsStringSync('x');

    final backup = await backUpBeforeMigration(
      dbFile,
      3,
      readSchemaVersion: (_) => stubVersion(3),
    );

    expect(backup, isNull);
  });

  test('does nothing on a downgrade', () async {
    // A file from a newer build. Copying would only leave a confusing artefact,
    // and this code has no business rewriting a schema it does not understand.
    dbFile.writeAsStringSync('x');

    final backup = await backUpBeforeMigration(
      dbFile,
      2,
      readSchemaVersion: (_) => stubVersion(5),
    );

    expect(backup, isNull);
  });

  test('skips the copy when the version cannot be read', () async {
    // An unreadable or corrupt file. Skipping is the safe failure: better no
    // backup than a copy step that mangles something this code cannot parse.
    dbFile.writeAsStringSync('not a database');

    final backup = await backUpBeforeMigration(
      dbFile,
      2,
      readSchemaVersion: (_) => throw const FormatException('unreadable'),
    );

    expect(backup, isNull);
  });

  test('overwrites an earlier backup of the same version', () async {
    // A migration that failed and is being retried. The current file is the
    // better copy, and two files claiming the same version would be worse.
    File('${dbFile.path}.backup-v1').writeAsStringSync('stale');
    dbFile.writeAsStringSync('current');

    final backup = await backUpBeforeMigration(
      dbFile,
      2,
      readSchemaVersion: (_) => stubVersion(1),
    );

    expect(backup!.readAsStringSync(), 'current');
  });

  group('against a real encrypted database, not a stub', () {
    // Every test above hands backUpBeforeMigration a stubbed readSchemaVersion,
    // which is what let the real one stay broken. It opened the file with no
    // key and threw `file is not a database` on every launch, because the file
    // is encrypted and its header is ciphertext like everything else. The
    // failure was caught and turned into "no backup", so section 5's
    // copy-before-migration had never once run -- and the first real migration
    // would have gone ahead with no recovery path, on an app that by design has
    // no cloud backup.
    //
    // These drive the real function against a real encrypted file.
    const key =
        'a3f1c8e2b74d09561fe8a2c4d70b13e95a6c8f20d1b4e7936ac5028de1f4b7c6';

    void writeEncryptedDatabaseAt(int version) {
      final database = sqlite3.open(dbFile.path);
      applyKeyAndVerify(database, key);
      database
        ..execute('CREATE TABLE period_starts (date TEXT);')
        ..execute("INSERT INTO period_starts VALUES ('2024-05-17');")
        ..userVersion = version;
      database.close();
    }

    test('the version can be read back out of an encrypted file', () {
      writeEncryptedDatabaseAt(1);

      expect(readSchemaVersionOf(dbFile.path, key: key), 1);
    });

    test('a copy is actually made when the schema is behind', () async {
      writeEncryptedDatabaseAt(1);

      final backup = await backUpBeforeMigration(
        dbFile,
        2,
        readSchemaVersion: (file) => readSchemaVersionOf(file.path, key: key),
      );

      expect(
        backup,
        isNotNull,
        reason: 'section 5 requires the copy, and it was never being made',
      );
      expect(backup!.path, '${dbFile.path}.backup-v1');
      expect(
        backup.readAsBytesSync(),
        dbFile.readAsBytesSync(),
        reason: 'the copy must be the database, byte for byte',
      );
    });

    test('the copy is still encrypted', () {
      // It is a byte copy of an encrypted file, so it must be -- but this is
      // the one artefact section 5 creates on disk and nothing else checks it.
      writeEncryptedDatabaseAt(1);
      final copy = dbFile.copySync('${dbFile.path}.backup-v1');

      expect(
        String.fromCharCodes(copy.readAsBytesSync()),
        isNot(contains('2024-05-17')),
      );
    });

    test('a wrong key throws rather than reading as version 0', () {
      // 0 means "fresh file, nothing to back up". A wrong key resolving to 0
      // would skip the copy exactly as quietly as the original bug did.
      writeEncryptedDatabaseAt(1);

      expect(
        () => readSchemaVersionOf(dbFile.path, key: 'f' * 64),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
