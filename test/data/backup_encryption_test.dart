import 'dart:io';

import 'package:period/data/backup/backup_document.dart';
import 'package:period/data/backup/backup_file.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

/// Proves an exported backup is actually encrypted.
///
/// Modelled on open_database_test.dart, and for the same reason: a green build
/// says nothing about which library got linked, and an unknown pragma is a
/// silent no-op. The only check worth trusting is writing a file and then
/// trying to read it without the passphrase.
///
/// This matters more for a backup than for the database. The database file
/// stays inside the app's private storage; a backup is handed to a share sheet
/// and may end up anywhere the user sends it.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('period_backup_cipher');
    file = File('${dir.path}/backup.period');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const passphrase = 'correct horse battery staple';
  const secret = 'period started today, worse than last month';

  BackupDocument documentWithNote([String note = secret]) => BackupDocument(
    exportedOn: aDate(2024, 5, 17),
    entries: [
      DayEntry(
        date: aDate(2024, 5, 17),
        flow: FlowIntensity.heavy,
        note: note,
        symptoms: const {},
      ),
    ],
  );

  test('the note never appears in the file on disk', () {
    // The bluntest possible check, and the one a worried user would do.
    writeBackupFile(file, documentWithNote(), passphrase);

    expect(
      String.fromCharCodes(file.readAsBytesSync()),
      isNot(contains(secret)),
      reason: 'the note is sitting in the backup unencrypted',
    );
  });

  test('the file does not announce itself as a database', () {
    writeBackupFile(file, documentWithNote(), passphrase);

    expect(
      String.fromCharCodes(file.readAsBytesSync().take(16).toList()),
      isNot(startsWith('SQLite format 3')),
      reason: 'an unencrypted SQLite file says so in its first 16 bytes',
    );
  });

  test('it cannot be read without the passphrase', () {
    writeBackupFile(file, documentWithNote(), passphrase);

    expect(
      () => readBackupFile(file, ''),
      throwsA(
        isA<BackupException>().having(
          (error) => error.problem,
          'problem',
          BackupProblem.couldNotOpen,
        ),
      ),
    );
  });

  test('it cannot be read with the wrong passphrase', () {
    writeBackupFile(file, documentWithNote(), passphrase);

    expect(
      () => readBackupFile(file, 'not the passphrase'),
      throwsA(isA<BackupException>()),
    );
  });

  test('it can be read with the right one', () {
    writeBackupFile(file, documentWithNote(), passphrase);

    final restored = readBackupFile(file, passphrase);
    expect(restored.entries.single.note, secret);
  });

  group('a passphrase is whatever a person typed', () {
    for (final awkward in [
      "it's a secret",
      'quote " and backslash \\',
      'Ärger mit Umlauten',
      '🩸🩸🩸',
      'a passphrase that is really rather a lot longer than any key '
          'this app has ever generated for itself',
    ]) {
      test('round-trips: $awkward', () {
        // Every key the app made for itself until now was generated hex and
        // could never contain a quote, so pragmaKeyStatement's escaping has
        // never actually had to work. Here it does.
        writeBackupFile(file, documentWithNote(), awkward);

        expect(readBackupFile(file, awkward).entries.single.note, secret);
        expect(
          () => readBackupFile(file, 'wrong'),
          throwsA(isA<BackupException>()),
        );
      });
    }
  });

  test('an apostrophe passphrase cannot be opened by its escaped form', () {
    // If the escaping were done by stripping rather than doubling, these two
    // would be the same passphrase and the file would open. It does not.
    writeBackupFile(file, documentWithNote(), "it's");

    expect(() => readBackupFile(file, 'its'), throwsA(isA<BackupException>()));
    expect(readBackupFile(file, "it's").entries, hasLength(1));
  });

  test('exporting over an existing file leaves nothing of the old one', () {
    writeBackupFile(file, documentWithNote('the first export'), passphrase);
    writeBackupFile(file, documentWithNote('the second export'), passphrase);

    final restored = readBackupFile(file, passphrase);
    expect(restored.entries, hasLength(1));
    expect(restored.entries.single.note, 'the second export');
    expect(
      String.fromCharCodes(file.readAsBytesSync()),
      isNot(contains('the first export')),
    );
  });
}
