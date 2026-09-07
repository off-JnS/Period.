import 'dart:convert';
import 'dart:io';

import 'package:period/data/backup/backup_document.dart';
import 'package:period/data/backup/backup_file.dart';
import 'package:period/data/backup/backup_service.dart';
import 'package:period/data/database/database.dart';
import 'package:period/data/database/encryption.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/database.dart';
import '../support/dates.dart';

/// Every way reading a backup can fail, and the fact that each one is
/// distinguishable.
///
/// A single "import failed" would leave the user with no idea whether to retype
/// the passphrase, pick a different file, or update the app. These are the four
/// answers, and the point of the tests is that they do not collapse into one.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('period_backup_format');
    file = File('${dir.path}/backup.period');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const passphrase = 'correct horse battery staple';

  Matcher throwsProblem(BackupProblem problem) => throwsA(
    isA<BackupException>().having((error) => error.problem, 'problem', problem),
  );

  /// Builds an encrypted container by hand, so a malformed backup can be made
  /// without the writer refusing to produce one.
  void writeRaw({int? version, String? payload, bool withTable = true}) {
    if (file.existsSync()) file.deleteSync();
    final database = sqlite3.open(file.path);
    applyKeyAndVerify(database, passphrase);
    if (withTable) {
      database
        ..execute(
          'CREATE TABLE $backupTableName ('
          'format_version INTEGER NOT NULL, payload TEXT NOT NULL);',
        )
        ..execute(
          'INSERT INTO $backupTableName (format_version, payload) '
          'VALUES (?, ?);',
          [version ?? 1, payload ?? '{}'],
        );
    } else {
      database.execute('CREATE TABLE something_else (a TEXT);');
    }
    database.close();
  }

  test('a file that is not a database at all', () {
    file.writeAsBytesSync(List.filled(2048, 7));

    expect(
      () => readBackupFile(file, passphrase),
      throwsProblem(BackupProblem.couldNotOpen),
    );
  });

  test('an encrypted database that is not a backup', () {
    writeRaw(withTable: false);

    expect(
      () => readBackupFile(file, passphrase),
      throwsProblem(BackupProblem.notABackup),
    );
  });

  test('a plain unencrypted SQLite file', () {
    // Opened with a passphrase it does not need, so it fails to decrypt. The
    // honest answer is "could not open", not a guess about which of the two.
    final plain = sqlite3.open(file.path);
    plain
      ..execute('CREATE TABLE t (a TEXT);')
      ..execute("INSERT INTO t VALUES ('hello');");
    plain.close();

    expect(
      () => readBackupFile(file, passphrase),
      throwsProblem(BackupProblem.couldNotOpen),
    );
  });

  group('written by a newer version', () {
    test('a newer format version is refused rather than half-read', () {
      writeRaw(
        version: BackupDocument.currentFormatVersion + 1,
        payload: jsonEncode({
          'formatVersion': BackupDocument.currentFormatVersion + 1,
          'exportedOn': '2024-05-17',
          'periodStarts': <String>[],
          'entries': <Object>[],
          'settings': <String, String>{},
        }),
      );

      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.newerFormat),
      );
    });

    test('a container claiming a newer version is refused before parsing', () {
      // The column is checked, not merely stored: a newer file is refused
      // before any of it is read, rather than after.
      writeRaw(
        version: BackupDocument.currentFormatVersion + 1,
        payload: jsonEncode({
          'formatVersion': BackupDocument.currentFormatVersion,
          'exportedOn': '2024-05-17',
          'periodStarts': <String>[],
          'entries': <Object>[],
          'settings': <String, String>{},
        }),
      );

      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.newerFormat),
      );
    });

    test('a flow value this build does not know is refused, not dropped', () {
      // Silently dropping it would lose something the user recorded, which is
      // the exact failure a backup exists to prevent.
      writeRaw(
        payload: jsonEncode({
          'formatVersion': 1,
          'exportedOn': '2024-05-17',
          'periodStarts': <String>[],
          'entries': [
            {'date': '2024-05-17', 'flow': 'torrential'},
          ],
          'settings': <String, String>{},
        }),
      );

      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.newerFormat),
      );
    });
  });

  group('damaged', () {
    test('a payload that is not JSON', () {
      writeRaw(payload: 'not json at all');
      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.damaged),
      );
    });

    test('JSON that is not a backup document', () {
      writeRaw(payload: jsonEncode({'hello': 'world'}));
      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.damaged),
      );
    });

    test('a date that is not a date', () {
      writeRaw(
        payload: jsonEncode({
          'formatVersion': 1,
          'exportedOn': 'the seventeenth',
          'periodStarts': <String>[],
          'entries': <Object>[],
          'settings': <String, String>{},
        }),
      );
      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.damaged),
      );
    });

    test('an entry missing its date', () {
      writeRaw(
        payload: jsonEncode({
          'formatVersion': 1,
          'exportedOn': '2024-05-17',
          'periodStarts': <String>[],
          'entries': [
            {'note': 'a note and nothing else'},
          ],
          'settings': <String, String>{},
        }),
      );
      expect(
        () => readBackupFile(file, passphrase),
        throwsProblem(BackupProblem.damaged),
      );
    });
  });

  group('a failed import leaves the existing data alone', () {
    late AppDatabase db;

    setUp(() => db = aDatabase());
    tearDown(() => db.close());

    test('when the file cannot be read', () async {
      await db.logDao.addPeriodStart(aDate(2024, 3, 20));
      file.writeAsBytesSync(List.filled(2048, 7));

      await expectLater(
        BackupService(db).importFrom(file, passphrase: passphrase),
        throwsA(isA<BackupException>()),
      );
      expect(await db.logDao.allPeriodStarts(), [aDate(2024, 3, 20)]);
    });

    test('when the backup holds a cycle mode this build cannot read', () async {
      // Caught while the transaction is still open, so she is left where she
      // started rather than with her old data gone and an app that will not
      // launch.
      await db.logDao.addPeriodStart(aDate(2024, 3, 20));
      await db.settingsDao.writeCycleSettings(
        const CycleSettings(mode: CycleMode.pregnancy),
      );

      writeRaw(
        payload: jsonEncode({
          'formatVersion': 1,
          'exportedOn': '2024-05-17',
          'periodStarts': ['2024-01-01'],
          'entries': <Object>[],
          'settings': {'cycle_mode': 'a_mode_from_the_future'},
        }),
      );

      await expectLater(
        BackupService(db).importFrom(file, passphrase: passphrase),
        throwsProblem(BackupProblem.newerFormat),
      );

      expect(await db.logDao.allPeriodStarts(), [aDate(2024, 3, 20)]);
      expect(
        (await db.settingsDao.readSettings()).cycle.mode,
        CycleMode.pregnancy,
      );
    });
  });

  test('an entry with no flow, note or symptoms is still a logged day', () {
    final document = BackupDocument(
      exportedOn: aDate(2024, 5, 17),
      entries: [DayEntry(date: aDate(2024, 5, 17), symptoms: const {})],
    );
    writeBackupFile(file, document, passphrase);

    final restored = readBackupFile(file, passphrase);
    expect(restored.entries, hasLength(1));
    expect(restored.entries.single.flow, isNull);
  });
}
