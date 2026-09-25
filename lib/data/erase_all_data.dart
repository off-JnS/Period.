import 'dart:io';

import 'database/database.dart';
import 'database/open_database.dart';
import 'database_key_store.dart';
import 'reminders/reminder_scheduler.dart';

/// CLAUDE.md §9: "Delete all data" must actually delete.
///
/// So this removes the database *file*, not just its rows. SQLite leaves
/// deleted rows in free pages until they are overwritten, and a file whose
/// tables were emptied can still hold them. Deleting the file, its journal,
/// and every pre-migration backup, and then the key that encrypted them,
/// leaves nothing of hers that can be read back -- the state of a fresh
/// install.
///
/// Order matters:
/// 1. Reminders are cancelled first, so none fires about data that is gone.
/// 2. The database is closed, so no write lands mid-deletion.
/// 3. The files go before the key. If a file cannot be deleted this throws
///    with the key still in place, so her data stays readable rather than
///    stranded behind a key that no longer exists.
Future<void> eraseAllData({
  required AppDatabase database,
  required Directory directory,
  required DatabaseKeyStore keyStore,
  required ReminderScheduler reminders,
}) async {
  try {
    await reminders.cancelAll();
  } on Object {
    // A reminder left behind reads only "Reminder" and reveals nothing;
    // failing to cancel one must not stop the data being deleted.
  }
  await database.close();
  deleteDatabaseFiles(directory);
  await keyStore.deleteKey();
}

/// Deletes the database file and everything derived from it in [directory]:
/// SQLite's journal and write-ahead files, and every `.backup-v<n>` copy.
/// Anything else in the directory is left alone. Throws if a file cannot be
/// deleted.
void deleteDatabaseFiles(Directory directory) {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name == databaseFileName ||
        name.startsWith('$databaseFileName-') ||
        name.startsWith('$databaseFileName.backup-v')) {
      entity.deleteSync();
    }
  }
}
