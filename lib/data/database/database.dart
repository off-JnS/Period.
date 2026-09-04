import 'dart:io';

import 'package:drift/drift.dart';

// The generated part below is compiled into this library, so the types its
// columns map to have to be visible here even though this file names few of
// them directly.
import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import 'converters.dart';
import 'daos/log_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// The on-device database.
///
/// Schema version 1. Read section 5 before changing anything here: there is no
/// cloud backup and no recovery path, so a broken migration destroys a user's
/// data permanently. Migrations are additive only, a shipped one is never
/// edited, and every one needs a test that builds the previous schema, fills it
/// with realistic data, migrates, and asserts the data survived.
///
/// Note what has no table: cycle length, average length, predicted next period,
/// current phase, cycle day number, fertile window. Section 4 computes all of
/// them on read from [PeriodStarts], because users retroactively correct start
/// dates constantly and any stored derivative is stale from that moment on.
@DriftDatabase(tables: [PeriodStarts, DayEntries, DaySymptoms], daos: [LogDao])
class AppDatabase extends _$AppDatabase {
  /// Opens the database over [executor].
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      // Nothing to do yet -- version 1 is the first schema, so this branch is
      // unreachable today. It is written now, while there is nothing to lose,
      // rather than under pressure during a real migration.
      //
      // Whoever adds the first migration: the file has already been copied to
      // <db>.backup-v<from> by backUpBeforeMigration before this runs. Add the
      // step here, never edit an earlier one, and write the round-trip test
      // section 5 requires before shipping it.
      throw StateError('No migration from schema $from to $to exists yet');
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
