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
extension DatabaseKeySafety on String {
  /// A redacted form safe to appear in an error message.
  String get redactedKey => '<${utf8.encode(this).length} byte key, redacted>';
}
