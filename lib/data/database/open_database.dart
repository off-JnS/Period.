import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../database_key_store.dart';
import 'database.dart';
import 'encryption.dart';

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
/// [applyKeyAndVerify] in encryption.dart is what stops that being a silent
/// failure, and open_database_test.dart proves it end to end by reopening a
/// written file without the key.
Future<OpenedDatabase> openEncryptedDatabase({
  DatabaseKeyStore? keyStore,
}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$databaseFileName');

  // The key is read first because the backup below needs it. Reading the
  // schema version means reading the database, and the database is encrypted.
  final key = await (keyStore ?? SecureDatabaseKeyStore()).readOrCreateKey();

  // Section 5: copy the file before any migration touches it. Runs here rather
  // than inside the migration because by then a transaction is already open and
  // the copy would capture a half-migrated database.
  await backUpBeforeMigration(
    file,
    AppDatabase(NativeDatabase.memory()).schemaVersion,
    readSchemaVersion: (file) => readSchemaVersionOf(file.path, key: key),
  );

  return OpenedDatabase(
    database: AppDatabase(
      NativeDatabase(
        file,
        setup: (database) => applyKeyAndVerify(database, key),
      ),
    ),
    documents: directory,
  );
}

/// An opened database and the directory it lives in.
///
/// The directory is returned rather than asked for again, so that section 9's
/// delete removes the migration copies from the same place section 5 wrote
/// them, instead of from wherever a second lookup happened to point.
class OpenedDatabase {
  /// Creates the pair.
  const OpenedDatabase({required this.database, required this.documents});

  /// The opened, decrypted database.
  final AppDatabase database;

  /// The directory holding the database file and its `.backup-v<n>` copies.
  final Directory documents;
}
