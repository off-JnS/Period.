import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file to the system share sheet. A parameter so tests need no
/// platform channel.
typedef FileSharer = Future<void> Function(XFile file, Rect? origin);

/// The real share sheet.
Future<void> systemShare(XFile file, Rect? origin) => SharePlus.instance.share(
  ShareParams(files: [file], sharePositionOrigin: origin),
);

/// Writes [bytes] to a temporary PDF named [fileName], shares it, and deletes
/// it again once the share sheet is done.
///
/// Temporary, and deleted afterwards: the report is her history in readable
/// form, so it should exist outside the encrypted database only as long as it
/// takes to send it where she chose.
Future<void> sharePdf(
  Uint8List bytes, {
  required String fileName,
  FileSharer share = systemShare,
  Rect? origin,
  Future<Directory> Function() directory = getTemporaryDirectory,
}) async {
  final dir = await directory();
  final file = File('${dir.path}/$fileName.pdf');
  await file.writeAsBytes(bytes, flush: true);
  try {
    await share(XFile(file.path, mimeType: 'application/pdf'), origin);
  } finally {
    if (file.existsSync()) await file.delete();
  }
}
