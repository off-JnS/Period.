import 'dart:io';

import '../../domain/models/cycle_date.dart';
import '../database/database.dart';
import 'backup_document.dart';
import 'backup_file.dart';

/// Makes and restores backups.
///
/// Section 1 promises the data never leaves the device by itself. A backup is
/// the one exception the user asks for, so it is encrypted with a passphrase
/// only she has: the app cannot read a backup it made, which is the property
/// that makes handing the file to a share sheet acceptable at all.
class BackupService {
  /// Creates the service.
  const BackupService(this._database);

  final AppDatabase _database;

  /// Everything stored, as a document.
  Future<BackupDocument> buildDocument(CycleDate today) async {
    return BackupDocument(
      exportedOn: today,
      periodStarts: await _database.logDao.allPeriodStarts(),
      entries: await _database.logDao.allEntries(),
      settings: await _database.settingsDao.readAll(),
    );
  }

  /// Writes an encrypted backup of everything to [file].
  Future<void> exportTo(
    File file, {
    required CycleDate today,
    required String passphrase,
  }) async {
    writeBackupFile(file, await buildDocument(today), passphrase);
  }

  /// Replaces everything stored with the contents of [file].
  ///
  /// Replace, not merge. Two entries for the same day with different notes have
  /// no correct resolution, and inventing one is exactly what section 11 rules
  /// out. The UI says plainly that this is what happens before it is called.
  ///
  /// The whole restore runs in one transaction, so a file that turns out to be
  /// unreadable part-way through leaves the existing data untouched rather than
  /// half-replaced.
  Future<void> importFrom(File file, {required String passphrase}) async {
    final document = readBackupFile(file, passphrase);

    await _database.transaction(() async {
      await _database.logDao.deleteEverything();

      for (final date in document.periodStarts) {
        await _database.logDao.addPeriodStart(date);
      }
      for (final entry in document.entries) {
        await _database.logDao.saveEntry(entry);
      }
      await _database.settingsDao.replaceAll(document.settings);

      // Read the settings back before committing. A backup carrying a cycle
      // mode this build cannot read would otherwise import cleanly and then
      // fail on the next launch, with the old data already gone. Failing here
      // rolls the transaction back and leaves her where she started.
      try {
        await _database.settingsDao.readSettings();
      } on StateError {
        throw const BackupException(BackupProblem.newerFormat);
      }
    });
  }
}
