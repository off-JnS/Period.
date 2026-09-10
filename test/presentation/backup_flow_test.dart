import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/backup/backup_service.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/presentation/providers.dart';
import 'package:period/presentation/settings/settings_page.dart';
import 'package:period/presentation/settings/settings_screen.dart';

import '../support/backup.dart';
import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/widgets.dart';

/// Export and restore, driven through the real screen against a real database
/// and a real encrypted file.
///
/// Only the share sheet and the file picker are faked. Everything else --
/// the encryption, the file on disk, the transaction -- is the code that ships.
void main() {
  late AppDatabase db;
  late Directory documents;
  late Directory dir;
  late FakeBackupTransfer transfer;

  const passphrase = 'correct horse battery staple';

  setUp(() {
    db = aDatabase();
    documents = Directory.systemTemp.createTempSync('period_documents');
    addTearDown(() => documents.deleteSync(recursive: true));
    dir = Directory.systemTemp.createTempSync('period_backup_flow');
    transfer = FakeBackupTransfer(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(FixedClock(aDate(2024, 5, 17))),
    backupTransferProvider.overrideWithValue(transfer),
    documentsDirectoryProvider.overrideWithValue(documents),
  ];

  Future<void> pumpSettings(WidgetTester tester) async {
    await pumpWithDatabase(
      tester,
      const SettingsPage(),
      database: db,
      overrides: overrides(),
      surface: const Size(400, 1100),
    );
  }

  Future<void> tapRow(WidgetTester tester, String label) async {
    await tester.dragUntilVisible(
      find.text(label),
      find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ListView),
      ),
      const Offset(0, -100),
    );
    await settleDatabase(tester);
    await tester.tap(find.text(label));
    await settleDatabase(tester);
  }

  Future<void> typePassphrase(
    WidgetTester tester,
    String value, {
    String? again,
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, value);
    if (again != null) await tester.enterText(fields.last, again);
    await settleDatabase(tester);
  }

  Future<void> exportBackup(WidgetTester tester) async {
    await tapRow(tester, 'Export a backup');
    await typePassphrase(tester, passphrase, again: passphrase);
    // The confirming button carries the action's name, not "OK".
    await tester.tap(find.widgetWithText(FilledButton, 'Export a backup'));
    await settleDatabase(tester);
  }

  Future<void> restoreBackup(
    WidgetTester tester, {
    String using = passphrase,
  }) async {
    await tapRow(tester, 'Restore from a backup');
    await tester.tap(find.widgetWithText(TextButton, 'Replace'));
    await settleDatabase(tester);
    await typePassphrase(tester, using);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await settleDatabase(tester);
  }

  group('exporting', () {
    testWidgets('writes an encrypted file and hands it on', (tester) async {
      await db.logDao.addPeriodStart(aDate(2024, 5, 12));
      await pumpSettings(tester);

      await exportBackup(tester);

      expect(find.text('Backup ready to save'), findsOneWidget);
      expect(transfer.sent, isTrue);
      expect(
        String.fromCharCodes(
          transfer.sentCopy!.readAsBytesSync().take(16).toList(),
        ),
        isNot(startsWith('SQLite format 3')),
        reason: 'the file handed to the share sheet is not encrypted',
      );
    });

    testWidgets(
      'the file is named for the day it was made, with an extension',
      (tester) async {
        // The extension is what Android derives a MIME type from and iOS a UTI.
        // Without one, share targets refuse the file or rename it.
        await pumpSettings(tester);
        await exportBackup(tester);

        expect(
          transfer.written!.path,
          endsWith('period-backup-2024-05-17.period'),
        );
      },
    );

    testWidgets('no copy is left behind in the app once it is handed on', (
      tester,
    ) async {
      // fileToWrite justifies temporary storage on the grounds that a second
      // copy of her data has no business in the app's own storage. That is only
      // true if something removes it.
      await pumpSettings(tester);
      await exportBackup(tester);

      expect(transfer.sentCopy, isNotNull, reason: 'nothing was shared');
      expect(
        transfer.written!.existsSync(),
        isFalse,
        reason: 'the export is still sitting in app storage',
      );
    });

    testWidgets('the share sheet is told where to appear from', (tester) async {
      // iPad presents it as a popover and refuses to show one without a source
      // rectangle, so without this the export can never leave the device.
      await pumpSettings(tester);
      await exportBackup(tester);

      expect(transfer.origin, isNotNull);
      expect(transfer.origin!.width, greaterThan(0));
    });

    testWidgets('says the passphrase cannot be recovered, before she types', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapRow(tester, 'Export a backup');

      expect(
        find.textContaining('cannot be opened without it'),
        findsOneWidget,
      );
      expect(find.textContaining('Nobody can recover it'), findsOneWidget);
    });

    testWidgets('a mistyped confirmation is refused, not exported', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tapRow(tester, 'Export a backup');
      await typePassphrase(tester, passphrase, again: 'something else');
      await tester.tap(find.widgetWithText(FilledButton, 'Export a backup'));
      await settleDatabase(tester);

      expect(find.text('These do not match'), findsOneWidget);
      expect(transfer.written, isNull);
    });

    testWidgets('a too-short passphrase is refused', (tester) async {
      await pumpSettings(tester);
      await tapRow(tester, 'Export a backup');
      await typePassphrase(tester, 'short', again: 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Export a backup'));
      await settleDatabase(tester);

      expect(find.textContaining('At least 8'), findsOneWidget);
      expect(transfer.written, isNull);
    });

    testWidgets('backing out exports nothing', (tester) async {
      await pumpSettings(tester);
      await tapRow(tester, 'Export a backup');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleDatabase(tester);

      expect(transfer.written, isNull);
      expect(transfer.sent, isFalse);
    });
  });

  group('restoring', () {
    /// Makes a real backup file holding [starts], the way the app would.
    Future<File> aBackupContaining(List<int> days) async {
      final other = aDatabase();
      for (final day in days) {
        await other.logDao.addPeriodStart(aDate(2024, 4, day));
      }
      final file = File('${dir.path}/from-elsewhere');
      await BackupService(other)
          .exportTo(file, today: aDate(2024, 5, 1), passphrase: passphrase);
      await other.close();
      return file;
    }

    testWidgets('replaces everything with the backup', (tester) async {
      await db.logDao.addPeriodStart(aDate(2024, 5, 12));
      transfer.toChoose = await aBackupContaining([3, 30]);
      await pumpSettings(tester);

      await restoreBackup(tester);

      expect(find.text('Backup restored'), findsOneWidget);
      expect(await db.logDao.allPeriodStarts(), [
        aDate(2024, 4, 3),
        aDate(2024, 4, 30),
      ]);
    });

    testWidgets('says what replace means before asking for the passphrase', (
      tester,
    ) async {
      transfer.toChoose = await aBackupContaining([3]);
      await pumpSettings(tester);

      await tapRow(tester, 'Restore from a backup');
      expect(find.text('Replace everything?'), findsOneWidget);
      expect(find.textContaining('will be gone'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('backing out of the confirmation changes nothing', (
      tester,
    ) async {
      await db.logDao.addPeriodStart(aDate(2024, 5, 12));
      transfer.toChoose = await aBackupContaining([3]);
      await pumpSettings(tester);

      await tapRow(tester, 'Restore from a backup');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleDatabase(tester);

      expect(await db.logDao.allPeriodStarts(), [aDate(2024, 5, 12)]);
    });

    testWidgets('the wrong passphrase says so and changes nothing', (
      tester,
    ) async {
      await db.logDao.addPeriodStart(aDate(2024, 5, 12));
      transfer.toChoose = await aBackupContaining([3]);
      await pumpSettings(tester);

      await restoreBackup(tester, using: 'not the passphrase');

      expect(find.textContaining('did not open this file'), findsOneWidget);
      expect(await db.logDao.allPeriodStarts(), [aDate(2024, 5, 12)]);
    });

    testWidgets('a file that cannot be opened at all still says something', (
      tester,
    ) async {
      // sqlite3.open throws outside readBackupFile's own try block, so this
      // used to escape as an unhandled exception and the restore appeared to
      // do nothing whatsoever.
      final directory = Directory('${dir.path}/not-a-file')..createSync();
      transfer.toChoose = File(directory.path);
      await pumpSettings(tester);

      await restoreBackup(tester);

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a file that is not a backup says so', (tester) async {
      final notABackup = File('${dir.path}/holiday.jpg')
        ..writeAsBytesSync(List.filled(2048, 7));
      transfer.toChoose = notABackup;
      await pumpSettings(tester);

      await restoreBackup(tester);

      expect(find.textContaining('did not open this file'), findsOneWidget);
    });

    testWidgets('choosing no file does nothing at all', (tester) async {
      transfer.toChoose = null;
      await pumpSettings(tester);

      await tapRow(tester, 'Restore from a backup');

      expect(find.text('Replace everything?'), findsNothing);
    });

    testWidgets('the restored cycle mode reaches the screen', (tester) async {
      final other = aDatabase();
      await other.settingsDao.writeCycleSettings(
        const CycleSettings(mode: CycleMode.pregnancy),
      );
      final file = File('${dir.path}/with-mode');
      await BackupService(other)
          .exportTo(file, today: aDate(2024, 5, 1), passphrase: passphrase);
      await other.close();
      transfer.toChoose = file;

      await pumpSettings(tester);
      await restoreBackup(tester);

      expect(
        tester
            .widget<RadioGroup<CycleMode>>(find.byType(RadioGroup<CycleMode>))
            .groupValue,
        CycleMode.pregnancy,
      );
    });
  });

  testWidgets('a full round trip through the screen', (tester) async {
    await db.logDao.addPeriodStart(aDate(2024, 5, 12));
    await db.logDao.saveEntry(
      aDayEntry(date: aDate(2024, 5, 12), note: 'the first day'),
    );
    await pumpSettings(tester);

    await exportBackup(tester);
    // Restored from the copy that left the app, not from the app's own
    // temporary file -- which is deleted, and which she would never see.
    transfer.toChoose = transfer.sentCopy;

    await tapRow(tester, 'Delete all data');
    await tester.tap(find.text('Delete everything'));
    await settleDatabase(tester);
    expect(await db.logDao.allPeriodStarts(), isEmpty);

    await restoreBackup(tester);

    expect(await db.logDao.allPeriodStarts(), [aDate(2024, 5, 12)]);
    expect(
      (await db.logDao.entryOn(aDate(2024, 5, 12)))!.note,
      'the first day',
    );
  });
}
