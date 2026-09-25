import 'dart:io';

import 'package:drift/native.dart';
import 'package:period/data/database/database.dart';
import 'package:period/data/database/open_database.dart';
import 'package:period/data/database_key_store.dart';
import 'package:period/data/erase_all_data.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:test/test.dart';

import '../support/dates.dart';
import '../support/fake_reminder_scheduler.dart';
import '../support/fake_widget_bridge.dart';
import '../support/models.dart';

class _FakeKeyStore implements DatabaseKeyStore {
  bool deleted = false;

  @override
  Future<String> readOrCreateKey() async => 'key';

  @override
  Future<void> deleteKey() async => deleted = true;
}

void main() {
  late Directory dir;
  late File dbFile;
  late AppDatabase database;
  late _FakeKeyStore keyStore;
  late FakeReminderScheduler reminders;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('period_erase_test');
    dbFile = File('${dir.path}/$databaseFileName');
    // Plain sqlite in tests; what is under test is which files go, not the
    // cipher.
    database = AppDatabase(NativeDatabase(dbFile));
    keyStore = _FakeKeyStore();
    reminders = FakeReminderScheduler();

    // A realistic history, so there is something in the file to lose.
    await database.logDao.addPeriodStart(aDate(2024, 4, 3));
    await database.logDao.addPeriodStart(aDate(2024, 5, 1));
    await database.logDao.saveEntry(
      aDayEntry(date: aDate(2024, 5, 1), note: 'private'),
    );
    await database.settingsDao.saveCycleSettings(
      const CycleSettings(mode: CycleMode.pregnancy),
    );

    File('${dbFile.path}.backup-v1').writeAsStringSync('old copy');
    File('${dbFile.path}-journal').writeAsStringSync('journal');
    File('${dir.path}/unrelated.txt').writeAsStringSync('keep me');
  });

  tearDown(() {
    Process.runSync('chmod', ['-R', 'u+w', dir.path]);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> erase() => eraseAllData(
    database: database,
    directory: dir,
    keyStore: keyStore,
    reminders: reminders,
  );

  test('the database file itself is gone, not just emptied', () async {
    expect(dbFile.existsSync(), isTrue);
    await erase();
    expect(dbFile.existsSync(), isFalse);
  });

  test('journal and pre-migration backups go with it', () async {
    await erase();
    final left = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(left, {'unrelated.txt'});
  });

  test('the encryption key is forgotten', () async {
    await erase();
    expect(keyStore.deleted, isTrue);
  });

  test('scheduled reminders are cancelled', () async {
    await erase();
    expect(reminders.cancelled, 1);
  });

  test(
    'a reminder that cannot be cancelled does not stop the deletion',
    () async {
      final failing = _FailingScheduler();
      await eraseAllData(
        database: database,
        directory: dir,
        keyStore: keyStore,
        reminders: failing,
      );
      expect(dbFile.existsSync(), isFalse);
      expect(keyStore.deleted, isTrue);
    },
  );

  test('if the files cannot be deleted, the key is kept', () async {
    // Losing the key with the file still there would strand her data behind
    // a key that no longer exists. Read-only directory: deletes fail.
    Process.runSync('chmod', ['a-w', dir.path]);
    await expectLater(erase(), throwsA(isA<FileSystemException>()));
    expect(keyStore.deleted, isFalse);
    expect(dbFile.existsSync(), isTrue);
  });

  test('a directory that does not exist is not an error', () {
    expect(
      () => deleteDatabaseFiles(Directory('${dir.path}/missing')),
      returnsNormally,
    );
  });

  test("the widget's snapshot is cleared too", () async {
    final widget = FakeWidgetBridge();
    await eraseAllData(
      database: database,
      directory: dir,
      keyStore: keyStore,
      reminders: reminders,
      widget: widget,
    );
    expect(widget.cleared, 1);
  });
}

class _FailingScheduler extends FakeReminderScheduler {
  @override
  Future<void> cancelAll() => Future.error(StateError('no platform'));
}
