import 'dart:io';

import 'package:period/data/database/open_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Proves the database is actually encrypted.
///
/// This is the test that should have existed from the moment schema v1 shipped.
/// Encryption was configured through a plugin package that the current sqlite3
/// no longer uses, so `PRAGMA key` was being silently ignored and the database
/// written in the clear -- and nothing failed, because an unknown pragma is a
/// no-op in SQLite and a green build says nothing about which library got
/// bundled.
///
/// The only check worth trusting is the one below: write a file with a key,
/// then try to read it without one.
void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('period_cipher_test');
    path = '${dir.path}/test.sqlite';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const key =
      'a3f1c8e2b74d09561fe8a2c4d70b13e95a6c8f20d1b4e7936ac5028de1f4b7c6';

  test('this build supports encryption at all', () {
    // If this fails, nothing else in this file means anything: PRAGMA key would
    // be a silent no-op and every other assertion would pass against plaintext.
    final database = sqlite3.open(path);
    addTearDown(database.close);

    expect(
      () => applyKeyAndVerify(database, key),
      returnsNormally,
      reason: 'check the hooks.user_defines block in pubspec.yaml',
    );
  });

  test('a written database cannot be read without the key', () {
    final written = sqlite3.open(path);
    applyKeyAndVerify(written, key);
    written
      ..execute('CREATE TABLE secrets (note TEXT);')
      ..execute("INSERT INTO secrets VALUES ('period started today');");
    written.close();

    final withoutKey = sqlite3.open(path);
    addTearDown(withoutKey.close);
    expect(
      () => withoutKey.select('SELECT * FROM secrets;'),
      throwsA(isA<SqliteException>()),
      reason: 'an unencrypted file would simply return the row',
    );
  });

  test('the plaintext never appears in the file on disk', () {
    // The bluntest possible check, and the one a worried user would do.
    final database = sqlite3.open(path);
    applyKeyAndVerify(database, key);
    database
      ..execute('CREATE TABLE secrets (note TEXT);')
      ..execute("INSERT INTO secrets VALUES ('period started today');");
    database.close();

    final bytes = File(path).readAsBytesSync();
    expect(
      String.fromCharCodes(bytes),
      isNot(contains('period started today')),
      reason: 'the logged text is sitting in the file unencrypted',
    );
    expect(
      String.fromCharCodes(bytes.take(16).toList()),
      isNot(startsWith('SQLite format 3')),
      reason: 'an unencrypted database announces itself in its first 16 bytes',
    );
  });

  test('the same key reads it back', () {
    final written = sqlite3.open(path);
    applyKeyAndVerify(written, key);
    written
      ..execute('CREATE TABLE secrets (note TEXT);')
      ..execute("INSERT INTO secrets VALUES ('period started today');");
    written.close();

    final reopened = sqlite3.open(path);
    applyKeyAndVerify(reopened, key);
    addTearDown(reopened.close);

    expect(
      reopened.select('SELECT note FROM secrets;').single['note'],
      'period started today',
    );
  });

  test('a different key does not', () {
    final written = sqlite3.open(path);
    applyKeyAndVerify(written, key);
    written.execute('CREATE TABLE secrets (note TEXT);');
    written.close();

    final wrongKey = sqlite3.open(path);
    addTearDown(wrongKey.close);
    // Applying a key never fails; it is the first read that does. Worth
    // asserting, because code that trusts the pragma's success as proof of a
    // correct key would be wrong.
    applyKeyAndVerify(
      wrongKey,
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    );
    expect(
      () => wrongKey.select('SELECT * FROM secrets;'),
      throwsA(isA<SqliteException>()),
    );
  });
}
