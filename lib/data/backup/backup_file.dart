import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../database/encryption.dart';
import 'backup_document.dart';

/// The table a backup file contains. One row, always.
const backupTableName = 'backup';

/// Writes [document] to [file], encrypted with [passphrase].
///
/// The file is an encrypted SQLite container holding the backup as JSON. The
/// container is what provides the encryption: it is the same
/// SQLite3MultipleCiphers build the app's own database uses, so the protection
/// on a backup is the same code, proven by the same tests, as the protection on
/// the database it came from.
///
/// There is no way to recover the contents without [passphrase]. That is the
/// point, and it is why the UI has to say so before the user picks one.
void writeBackupFile(File file, BackupDocument document, String passphrase) {
  // A stale file at this path would otherwise be opened and appended to, and
  // the old rows would come back on the next restore.
  if (file.existsSync()) file.deleteSync();

  final database = sqlite3.open(file.path);
  try {
    applyKeyAndVerify(database, passphrase);
    database.execute(
      'CREATE TABLE $backupTableName ('
      'format_version INTEGER NOT NULL, payload TEXT NOT NULL);',
    );
    database.execute(
      'INSERT INTO $backupTableName (format_version, payload) VALUES (?, ?);',
      [BackupDocument.currentFormatVersion, jsonEncode(document.toJson())],
    );
  } finally {
    database.close();
  }
}

/// Reads the backup in [file], decrypting it with [passphrase].
///
/// Throws [BackupException] for each way this can fail, so the UI can say which
/// one happened rather than "import failed".
BackupDocument readBackupFile(File file, String passphrase) {
  final database = sqlite3.open(file.path);
  try {
    applyKeyAndVerify(database, passphrase);

    final ResultSet rows;
    try {
      // The first actual read is where a wrong passphrase surfaces: PRAGMA key
      // accepts anything, and only decrypting a page proves it was right.
      rows = database.select(
        'SELECT format_version, payload FROM $backupTableName;',
      );
    } on SqliteException catch (error) {
      // A readable database without our table is somebody else's file. Anything
      // else -- a wrong passphrase, a photo, a truncated download -- comes back
      // from SQLite as "not a database", indistinguishably, so it is reported
      // as the one thing that is honestly known.
      throw BackupException(
        _looksLikeAnotherDatabase(error)
            ? BackupProblem.notABackup
            : BackupProblem.couldNotOpen,
      );
    }

    if (rows.length != 1) throw const BackupException(BackupProblem.damaged);

    final payload = rows.single['payload'];
    if (payload is! String) {
      throw const BackupException(BackupProblem.damaged);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const BackupException(BackupProblem.damaged);
    }
    if (decoded is! Map<String, Object?>) {
      throw const BackupException(BackupProblem.damaged);
    }

    return BackupDocument.fromJson(decoded);
  } finally {
    database.close();
  }
}

/// Whether [error] says the file opened but has no backup in it.
///
/// Matched on the message because sqlite3 reports a missing table and a failed
/// decrypt with different text but the same broad code. Getting this wrong only
/// changes which of two messages the user reads, never whether the import
/// happens, so a substring is an acceptable way to tell them apart.
bool _looksLikeAnotherDatabase(SqliteException error) =>
    error.message.contains('no such table');
