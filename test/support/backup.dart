import 'dart:io';

import 'package:period/data/backup/backup_transfer.dart';

/// A [BackupTransfer] backed by a real directory instead of a share sheet.
///
/// Lets the export and import flows be tested end to end -- a real encrypted
/// file really written and really read back -- without a platform plugin. The
/// only thing faked is where the file goes.
class FakeBackupTransfer implements BackupTransfer {
  /// Creates a transfer that writes into [directory].
  FakeBackupTransfer(this.directory);

  /// Where files are written.
  final Directory directory;

  /// The file the app chose to write, once it has.
  File? written;

  /// What [choose] returns. Null means the user backed out of the picker.
  File? toChoose;

  /// Whether the finished file was handed on.
  bool sent = false;

  @override
  Future<File> fileToWrite(String name) async =>
      written = File('${directory.path}/$name');

  @override
  Future<void> send(File file) async => sent = true;

  @override
  Future<File?> choose() async => toChoose;
}
