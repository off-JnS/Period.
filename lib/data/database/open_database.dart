import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

import '../database_key_store.dart';
import 'database.dart';

/// The database file's name inside the application support directory.
const databaseFileName = 'period.sqlite';

/// Thrown when the database cannot be opened as an encrypted one.
///
/// Deliberately fatal. Section 6 describes the failure this guards against: both
/// a plain and an encrypted sqlite3 can end up linked, the plain one can win,
/// and the result is an unencrypted database that behaves completely normally.
/// Nothing fails and nothing warns -- so this makes it fail and warn.
class DatabaseNotEncrypted implements Exception {
  /// Creates the error.
  const DatabaseNotEncrypted(this.detail);

  /// What was observed, for the log. Never contains the key.
  final String detail;

  @override
  String toString() => 'DatabaseNotEncrypted: $detail';
}

/// Opens the on-device encrypted database.
///
/// [keyStore] supplies the SQLCipher key, generating one on first launch. The
/// key never leaves this function and is never logged; see [DatabaseKeySafety].
///
/// The file lives in the application support directory rather than the documents
/// directory: documents is user-visible through iOS file sharing when an app
/// enables it, and a cycle database is not a document the user is meant to hand
/// around.
///
/// Throws [DatabaseNotEncrypted] when the sqlite3 that actually got linked is
/// not SQLCipher. Failing to start is the correct outcome there -- an app that
/// looks like it is saving to an encrypted store while writing plaintext is the
/// worse of the two failures, and section 1 names data leakage as one of the two
/// outcomes to treat as worst.
Future<AppDatabase> openEncryptedDatabase({
  required DatabaseKeyStore keyStore,
}) async {
  // Only does anything on old Android versions, where libsqlcipher.so
  // occasionally cannot be opened by the usual route. A no-op elsewhere.
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/$databaseFileName');
  await file.parent.create(recursive: true);

  final key = await keyStore.readOrCreateKey();

  return AppDatabase(
    NativeDatabase(
      file,
      setup: (rawDatabase) {
        // The key has to be the first statement on the connection: SQLCipher
        // reads the header with it, so anything executed before it would be
        // attempted against an undecrypted file.
        rawDatabase.execute(pragmaKeyStatement(key));
        verifyCipherIsActive(
          cipherVersion: () {
            final rows = rawDatabase.select('PRAGMA cipher_version;');
            if (rows.isEmpty) return null;
            final value = rows.first.values.first;
            return value is String ? value : value?.toString();
          },
          readSchemaVersion: () =>
              rawDatabase.select('PRAGMA user_version;').first.values.first,
        );

        // Section 5: copy the file before any migration touches it. This is
        // the first point the version is readable -- the header is encrypted
        // until the key above is applied -- and drift has not begun migrating
        // yet. Reading the version has also rolled back any journal a crash
        // left behind, so the copy is of a consistent file.
        //
        // A failed copy is allowed to throw. The app then reports that it
        // could not open the data and leaves the file exactly as it was,
        // which beats migrating with no way back.
        final current = rawDatabase
            .select('PRAGMA user_version;')
            .first
            .values
            .first;
        backUpBeforeMigrationSync(
          file,
          currentVersion: current is int ? current : 0,
          targetVersion: AppDatabase.currentSchemaVersion,
        );
      },
    ),
  );
}

/// Checks that the open connection is really SQLCipher and really keyed.
///
/// Split out from [openEncryptedDatabase] and driven by callbacks so it can be
/// tested without a device, a plugin or a native library. The two checks answer
/// different questions and both are needed:
///
/// - `PRAGMA cipher_version` returns nothing at all on a plain sqlite3 build.
///   That is the link-time mix-up section 6 warns about.
/// - Reading `user_version` forces SQLCipher to decrypt the header. A wrong or
///   missing key surfaces here rather than later, in the middle of a write.
void verifyCipherIsActive({
  required String? Function() cipherVersion,
  required Object? Function() readSchemaVersion,
}) {
  final String? version;
  try {
    version = cipherVersion();
  } on Object catch (error) {
    throw DatabaseNotEncrypted('cipher_version could not be read: $error');
  }

  if (version == null || version.isEmpty) {
    throw const DatabaseNotEncrypted(
      'PRAGMA cipher_version returned nothing, so the linked sqlite3 is not '
      'SQLCipher and this database would be written in plaintext',
    );
  }

  try {
    readSchemaVersion();
  } on Object catch (error) {
    throw DatabaseNotEncrypted(
      'the database header could not be decrypted with the stored key: $error',
    );
  }
}
