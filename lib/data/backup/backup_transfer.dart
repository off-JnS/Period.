import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// How a backup file leaves the app and comes back.
///
/// An interface for the same reason [DatabaseKeyStore] is one: it is the only
/// part of the backup that touches a platform plugin, so keeping it behind a
/// seam means the export and import flows can be tested without one, and the
/// choice of plugin stays revisitable.
abstract class BackupTransfer {
  /// A file to write a backup into, named [name].
  Future<File> fileToWrite(String name);

  /// Hands [file] to the system, so the user picks where it goes.
  Future<void> send(File file);

  /// Asks the user to choose a backup file, or null if she does not.
  Future<File?> choose();
}

/// The real transfer: the system share sheet out, the system file picker in.
class SystemBackupTransfer implements BackupTransfer {
  /// Creates the transfer.
  const SystemBackupTransfer();

  @override
  Future<File> fileToWrite(String name) async {
    // Temporary storage, not documents. The file is written only so it can be
    // handed straight to the share sheet; the copy the user keeps is wherever
    // she chose to put it, and leaving a second one in the app's own storage
    // would be a copy of her data nobody asked for.
    final directory = await getTemporaryDirectory();
    return File('${directory.path}/$name');
  }

  @override
  Future<void> send(File file) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Future<File?> choose() async {
    // Any file: the backup has a custom extension, and platforms differ on
    // whether they will filter by one they do not recognise. Better to let her
    // pick the wrong file and be told so than to hide the right one.
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.singleOrNull?.path;
    return path == null ? null : File(path);
  }
}
