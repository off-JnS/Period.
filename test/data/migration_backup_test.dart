import 'dart:io';

import 'package:period/data/database/database.dart';
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
}
