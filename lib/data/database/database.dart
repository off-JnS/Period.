import 'dart:io';

import 'package:drift/drift.dart';

// The generated part below is compiled into this library, so the types its
// columns map to have to be visible here even though this file names few of
// them directly.
import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import 'converters.dart';
import 'daos/log_dao.dart';
import 'daos/settings_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// The on-device database.
///
/// Schema version 2. Read section 5 before changing anything here: there is no
/// cloud backup and no recovery path, so a broken migration destroys a user's
/// data permanently. Migrations are additive only, a shipped one is never
/// edited, and every one needs a test that builds the previous schema, fills it
/// with realistic data, migrates, and asserts the data survived.
///
/// Note what has no table: cycle length, average length, predicted next period,
/// current phase, cycle day number, fertile window. Section 4 computes all of
/// them on read from [PeriodStarts], because users retroactively correct start
/// dates constantly and any stored derivative is stale from that moment on.
@DriftDatabase(
  tables: [PeriodStarts, DayEntries, DaySymptoms, AppSettings],
  daos: [LogDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database over [executor].
  AppDatabase(super.executor);

  /// The schema this build writes. Every change bumps it, and every bump adds a
  /// step to [migration] below; see the history there.
  static const currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      // The file has already been copied to <db>.backup-v<from> by
      // openEncryptedDatabase before this runs. Steps run in order and each is
      // guarded by the version it upgrades from, so a user several versions
      // behind passes through every one. Never edit a step that has shipped;
      // add the next one below it, with its round-trip test.

      // 1 -> 2: settings. Purely additive -- one new, empty table. No existing
      // table, column or row is touched, so there is nothing of hers here
      // that this step could damage. An empty table reads back as the
      // defaults, which is exactly what version 1 behaved as.
      if (from < 2) {
        await migrator.createTable(appSettings);
      }
    },
  );
}

/// Copies the database to `<db>.backup-v<version>` before a migration runs.
///
/// Section 5 requires this. It happens before the file is handed to drift, not
/// inside [MigrationStrategy.onUpgrade], because by then the migration is
/// already underway inside a transaction and a copy taken there would capture a
/// half-migrated file.
///
/// Returns the backup file when one was made, or null when the database is
/// absent, new, or already at [targetVersion]. A failure to read the existing
/// version is treated as "do not touch it": better to skip the copy than to
/// risk mangling a database this code does not understand.
Future<File?> backUpBeforeMigration(
  File databaseFile,
  int targetVersion, {
  required int Function(File file) readSchemaVersion,
}) async {
  if (!databaseFile.existsSync()) return null;

  final int current;
  try {
    current = readSchemaVersion(databaseFile);
  } on Object {
    return null;
  }

  // 0 means a fresh file drift has not written a schema into yet. Anything at
  // or beyond the target needs no backup -- and a version *above* the target is
  // a downgrade, where copying would only add a confusing artefact.
  if (current <= 0 || current >= targetVersion) return null;

  final backup = File('${databaseFile.path}.backup-v$current');
  await databaseFile.copy(backup.path);
  return backup;
}

/// Copies [databaseFile] to `<db>.backup-v<currentVersion>` when a migration
/// from [currentVersion] to [targetVersion] is about to run.
///
/// The synchronous twin of [backUpBeforeMigration], for the one place that
/// needs it: drift's connection `setup` callback, which is where the schema
/// version can first be read from an encrypted file (the key has to be applied
/// on that connection before the header is readable) and which cannot await.
/// It runs before drift starts the migration transaction, so the copy is of the
/// untouched file.
File? backUpBeforeMigrationSync(
  File databaseFile, {
  required int currentVersion,
  required int targetVersion,
}) {
  if (currentVersion <= 0 || currentVersion >= targetVersion) return null;
  final backup = File('${databaseFile.path}.backup-v$currentVersion');
  databaseFile.copySync(backup.path);
  return backup;
}
