import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../database_key_store.dart';
import 'database.dart';

/// The database file name. Kept out of line so the backup path derived from it
/// in [backUpBeforeMigration] cannot drift away from the real one.
const databaseFileName = 'period.sqlite';

/// Opens the on-device database, encrypted with SQLCipher.
///
/// This is where CLAUDE.md section 1's promise stops being a design intention
/// and becomes a file on disk. Read the whole function before changing any of
/// it; several steps look optional and are not.
///
/// The encrypting build of SQLite is selected by the `hooks.user_defines` block
/// in pubspec.yaml, not by any plugin package. sqlite3 3.x loads its native
/// library through Dart build hooks; the older sqlcipher_flutter_libs approach
/// does nothing there, which would leave the database in the clear.
///
/// `verifyEncryption` below is what stops that being a silent failure, and
/// open_database_test.dart proves it end to end by reopening a written file
/// without the key.
Future<AppDatabase> openEncryptedDatabase({DatabaseKeyStore? keyStore}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$databaseFileName');

  // Section 5: copy the file before any migration touches it. Runs here rather
  // than inside the migration because by then a transaction is already open and
  // the copy would capture a half-migrated database.
  await backUpBeforeMigration(
    file,
    AppDatabase(NativeDatabase.memory()).schemaVersion,
    readSchemaVersion: _readSchemaVersion,
  );

  final key = await (keyStore ?? SecureDatabaseKeyStore()).readOrCreateKey();

  return AppDatabase(
    NativeDatabase(file, setup: (database) => applyKeyAndVerify(database, key)),
  );
}

/// Reads the drift schema version already written into [file].
int _readSchemaVersion(File file) {
  final database = sqlite3.open(file.path);
  try {
    return database.userVersion;
  } finally {
    database.close();
  }
}

/// Applies [key] to [database] and refuses to continue unless it took effect.
///
/// The verification is the important half. An unknown pragma is a silent no-op
/// in SQLite, so on a plain build `PRAGMA key` succeeds, changes nothing, and
/// every subsequent query works perfectly against an unencrypted file. Nothing
/// fails and nothing warns. Checking that the pragma actually returned
/// something is what turns the worst possible outcome into a crash on launch.
void applyKeyAndVerify(Database database, String key) {
  database.execute(pragmaKeyStatement(key));

  final cipher = database.select('PRAGMA cipher;').singleOrNull;
  final active = cipher?.values.firstOrNull;
  if (active == null || active.toString().isEmpty) {
    throw StateError(
      'This build has no encryption support: PRAGMA cipher returned nothing, '
      'so PRAGMA key was silently ignored and the database would be written '
      'in the clear. Check the hooks.user_defines block in pubspec.yaml.',
    );
  }
}
