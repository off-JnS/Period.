import 'dart:io';

import 'package:period/data/backup/backup_service.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/domain/models/symptom.dart';
import 'package:test/test.dart';

import '../support/database.dart';
import '../support/dates.dart';

/// The round trip CLAUDE.md section 7 requires: export, wipe, import, and check
/// nothing was lost.
///
/// One honest deviation from the wording. Section 7 says "byte-identical", and
/// the exported *file* cannot be: it is encrypted, and encryption uses a fresh
/// salt each time, so two exports of the same data differ by design. What is
/// checked instead is stronger in the way that matters -- every row read back
/// out, compared field by field, with no extra rows and none missing.
void main() {
  late AppDatabase db;
  late Directory dir;
  late File file;

  const passphrase = 'correct horse battery staple';

  setUp(() {
    db = aDatabase();
    dir = Directory.systemTemp.createTempSync('period_backup');
    file = File('${dir.path}/backup.period');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  BackupService service() => BackupService(db);

  Future<void> exportWipeImport() async {
    await service().exportTo(
      file,
      today: aDate(2024, 5, 17),
      passphrase: passphrase,
    );
    await db.logDao.deleteEverything();
    expect(await db.logDao.allPeriodStarts(), isEmpty, reason: 'wipe failed');
    await service().importFrom(file, passphrase: passphrase);
  }

  test('an empty database round-trips to an empty database', () async {
    await exportWipeImport();

    expect(await db.logDao.allPeriodStarts(), isEmpty);
    expect(await db.logDao.allEntries(), isEmpty);
  });

  test('period starts survive, in order', () async {
    for (final start in [
      aDate(2024, 3, 20),
      aDate(2024, 4, 17),
      aDate(2024, 5, 15),
    ]) {
      await db.logDao.addPeriodStart(start);
    }

    await exportWipeImport();

    expect(await db.logDao.allPeriodStarts(), [
      aDate(2024, 3, 20),
      aDate(2024, 4, 17),
      aDate(2024, 5, 15),
    ]);
  });

  test('a fully filled entry survives field for field', () async {
    final entry = DayEntry(
      date: aDate(2024, 3, 20),
      flow: FlowIntensity.heavy,
      note: 'worse than last month',
      symptoms: {
        const Symptom(key: 'cramps'),
        const Symptom(key: 'headache'),
      },
    );
    await db.logDao.saveEntry(entry);

    await exportWipeImport();

    expect(await db.logDao.entryOn(aDate(2024, 3, 20)), entry);
  });

  test(
    'null keeps meaning "not recorded" rather than becoming empty',
    () async {
      await db.logDao.saveEntry(
        DayEntry(
          date: aDate(2024, 4, 1),
          flow: FlowIntensity.light,
          symptoms: const {},
        ),
      );

      await exportWipeImport();

      final restored = await db.logDao.entryOn(aDate(2024, 4, 1));
      expect(restored!.flow, FlowIntensity.light);
      expect(restored.note, isNull);
      expect(restored.symptoms, isEmpty);
    },
  );

  test('a day with symptoms and no entry row survives', () async {
    // The case an export that read only the entries table would drop silently.
    await db.logDao.saveEntry(
      DayEntry(
        date: aDate(2024, 4, 20),
        symptoms: {const Symptom(key: 'tiredness')},
      ),
    );
    await db.customStatement('DELETE FROM day_entries;');
    expect(await db.logDao.entryOn(aDate(2024, 4, 20)), isNotNull);

    await exportWipeImport();

    final restored = await db.logDao.entryOn(aDate(2024, 4, 20));
    expect(restored, isNotNull);
    expect(restored!.symptoms, {const Symptom(key: 'tiredness')});
  });

  test('a note with newlines, quotes and emoji survives intact', () async {
    const awkward = 'line one\nline "two"\ttabbed\n\'quoted\' 🩸 \\ backslash';
    await db.logDao.saveEntry(
      DayEntry(date: aDate(2024, 4, 5), note: awkward, symptoms: const {}),
    );

    await exportWipeImport();

    expect((await db.logDao.entryOn(aDate(2024, 4, 5)))!.note, awkward);
  });

  test('entries logged out of order come back in order', () async {
    for (final day in [12, 2, 27, 7]) {
      await db.logDao.saveEntry(
        DayEntry(date: aDate(2024, 4, day), symptoms: const {}),
      );
    }

    await exportWipeImport();

    expect(
      [for (final entry in await db.logDao.allEntries()) entry.date.day],
      [2, 7, 12, 27],
    );
  });

  for (final mode in CycleMode.values) {
    test('the ${mode.name} mode survives', () async {
      await db.settingsDao.writeCycleSettings(
        CycleSettings(mode: mode, predictionsOptedIn: true),
      );

      await exportWipeImport();

      final stored = await db.settingsDao.readSettings();
      expect(stored.cycle.mode, mode);
      expect(stored.cycle.predictionsOptedIn, isTrue);
    });
  }

  test('a setting this build has never heard of still round-trips', () async {
    // The format carries the settings rows raw, so a preference added in a
    // later version is not quietly dropped by an older one.
    await db.customStatement(
      'INSERT INTO settings (key, value) VALUES (?, ?);',
      ['some_future_setting', 'whatever'],
    );

    await exportWipeImport();

    expect(
      await db.settingsDao.readAll(),
      containsPair('some_future_setting', 'whatever'),
    );
  });

  test('importing replaces rather than merging', () async {
    await db.logDao.addPeriodStart(aDate(2024, 3, 20));
    await service().exportTo(
      file,
      today: aDate(2024, 5, 17),
      passphrase: passphrase,
    );

    // Logged after the export, and not in it.
    await db.logDao.addPeriodStart(aDate(2024, 4, 17));

    await service().importFrom(file, passphrase: passphrase);

    expect(await db.logDao.allPeriodStarts(), [aDate(2024, 3, 20)]);
  });

  test('the export records the day it was made', () async {
    final document = await service().buildDocument(aDate(2024, 5, 17));
    expect(document.exportedOn, aDate(2024, 5, 17));
  });

  test('a second export of the same data restores the same way', () async {
    await db.logDao.addPeriodStart(aDate(2024, 3, 20));
    final second = File('${dir.path}/again.period');

    await service().exportTo(
      file,
      today: aDate(2024, 5, 17),
      passphrase: passphrase,
    );
    await service().exportTo(
      second,
      today: aDate(2024, 5, 17),
      passphrase: passphrase,
    );

    // Not byte-identical, and must not be: a fresh salt each time is what stops
    // two backups of the same data being recognisably the same file.
    expect(file.readAsBytesSync(), isNot(second.readAsBytesSync()));

    await db.logDao.deleteEverything();
    await service().importFrom(second, passphrase: passphrase);
    expect(await db.logDao.allPeriodStarts(), [aDate(2024, 3, 20)]);
  });
}
