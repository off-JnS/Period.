import 'dart:io';

import 'database/database.dart';

/// Deletes her data and the copies of it, for CLAUDE.md section 9's "Delete all
/// data must actually delete".
///
/// Dropping the rows is only the first of three things, and on its own it left
/// two:
///
/// - **The migration copies.** `backUpBeforeMigration` writes
///   `<db>.backup-v<n>` beside the database, and nothing deleted them. Section
///   5 requires those copies to exist; section 9 requires this to remove them.
///   The settings screen's own comment says the app should come back "as a
///   fresh install, which is what someone deleting under pressure needs it to
///   mean", and a file of her entries sitting next to the database is not that.
/// - **The freed pages.** Deleting rows marks pages reusable; it does not
///   overwrite them, so her dates stayed in the file until something else
///   happened to need the space. `VACUUM` rewrites the database without them.
///
/// What this deliberately does **not** do is discard the encryption key. The
/// database is still in use afterwards, and a key that no longer opens it would
/// take the app down with the data. Rotating the key is a larger change than
/// this, and worth doing separately if it is wanted.
Future<void> eraseEverything(
  AppDatabase database, {
  required Directory documents,
}) async {
  await database.logDao.deleteEverything();

  // After the rows, not before: vacuuming first would only compact pages that
  // are about to be freed anyway.
  await database.customStatement('VACUUM;');

  for (final backup in migrationBackupsIn(documents)) {
    if (backup.existsSync()) backup.deleteSync();
  }
}
