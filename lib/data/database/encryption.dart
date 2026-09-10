import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Applies [key] to [database] and refuses to continue unless it took effect.
///
/// The verification is the important half. An unknown pragma is a silent no-op
/// in SQLite, so on a plain build `PRAGMA key` succeeds, changes nothing, and
/// every subsequent query works perfectly against an unencrypted file. Nothing
/// fails and nothing warns. Checking that the pragma actually returned
/// something is what turns the worst possible outcome into a crash on launch.
///
/// [key] may be a generated hex key, as the app's own database uses, or a
/// passphrase a person typed, as an exported backup uses. SQLite3MultipleCiphers
/// derives a key from either.
///
/// Note what this does **not** prove: that the key is the right one. A wrong key
/// applies without complaint and fails on the first read. Callers that accept a
/// key from a user have to read something to find out -- see
/// `data/backup/backup_file.dart`.
/// [readCipher] exists so a build *without* encryption can be simulated. It is
/// the only way to test the guard itself: on a build that links
/// SQLite3MultipleCiphers, `PRAGMA cipher` always answers, so every test would
/// pass whether or not this function checked anything -- which is how a guard
/// quietly stops guarding.
void applyKeyAndVerify(
  Database database,
  String key, {
  Object? Function(Database database) readCipher = _readCipher,
}) {
  database.execute(pragmaKeyStatement(key));

  final active = readCipher(database);
  if (active == null || active.toString().isEmpty) {
    throw StateError(
      'This build has no encryption support: PRAGMA cipher returned nothing, '
      'so PRAGMA key was silently ignored and the database would be written '
      'in the clear. Check the hooks.user_defines block in pubspec.yaml.',
    );
  }
}

/// Asks the database which cipher is active, or null on a build with none.
Object? _readCipher(Database database) =>
    database.select('PRAGMA cipher;').singleOrNull?.values.firstOrNull;

/// Escapes [key] for use in `PRAGMA key`.
///
/// The database's own key is generated hex and cannot contain a quote, but a
/// backup passphrase is whatever a person typed and very well might.
String pragmaKeyStatement(String key) {
  final escaped = key.replaceAll("'", "''");
  return "PRAGMA key = '$escaped'";
}

/// Never log or serialise a key or a passphrase. This exists to make that
/// explicit at the call site rather than relying on nobody being curious.
///
/// Nothing uses it today, and that is the right state of affairs: there is no
/// logging anywhere in `lib/`, so there is no call site to redact. It is here
/// for the first one that appears.
extension DatabaseKeySafety on String {
  /// A redacted form safe to appear in an error message.
  String get redactedKey => '<${utf8.encode(this).length} byte key, redacted>';
}

/// Reads the drift schema version written into the database at [path].
///
/// Applies [key] first, and that is the whole point. Without it this threw
/// `SqliteException(26): file is not a database` on every launch -- the file is
/// encrypted, so its header is ciphertext like everything else.
/// `backUpBeforeMigration` treats a failed read as "do not touch it" and
/// returns null, so section 5's copy-before-migration was silently never made.
/// The first real migration would have run with no recovery path, on an app
/// that by design has no cloud backup.
///
/// It stayed invisible because every test of `backUpBeforeMigration` stubs the
/// read out. `migration_backup_test.dart` now also drives this against a real
/// encrypted file.
///
/// Lives here rather than in `open_database.dart` so that it stays reachable
/// without dragging in `path_provider`, and because reading through a key is
/// this file's subject.
///
/// A wrong key throws rather than reading as version 0, which matters: 0 means
/// "fresh file, no backup needed" and would skip the copy just as quietly.
int readSchemaVersionOf(String path, {required String key}) {
  final database = sqlite3.open(path);
  try {
    applyKeyAndVerify(database, key);
    return database.userVersion;
  } finally {
    database.close();
  }
}
