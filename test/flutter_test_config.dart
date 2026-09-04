import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test under `test/`. Flutter picks this file up by name.
///
/// Its job is to load a real font, because without one the test environment
/// draws every glyph as a filled box. Golden files would still be stable and
/// still catch layout changes — but nobody could read them, and the point of
/// goldens here is that a person can review a screen without installing
/// anything.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  return testMain();
}

/// Loads Roboto and the Material icon font from the Flutter SDK.
///
/// The icon font matters as much as the text one here: section 9 forbids
/// carrying meaning by colour alone, so each state on the Today screen is
/// distinguished by an icon as well as its wording. Without the font those
/// icons render as empty boxes and the goldens could not show that the
/// distinction exists.
///
/// Taken from the SDK rather than vendored into the repository: the layout
/// `<sdk>/bin/cache/artifacts/material_fonts/` is fixed by Flutter itself, so
/// this resolves on any standard install including CI, and the repository stays
/// free of binary assets it does not ship.
Future<void> _loadFonts() async {
  final fonts = _materialFontsDirectory();
  if (fonts == null) {
    // Deliberately fatal. Falling back to the box font would silently produce
    // goldens that disagree with everyone else's, which is far more confusing
    // than a clear failure here.
    throw StateError(
      'Could not find the Flutter SDK material_fonts directory, so golden '
      'files would render with the placeholder font and would not match. '
      'Looked upwards from ${Platform.resolvedExecutable}.',
    );
  }

  await _load(fonts, 'Roboto', const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await _load(fonts, 'MaterialIcons', const ['MaterialIcons-Regular.otf']);
}

Future<void> _load(
  Directory fonts,
  String family,
  List<String> fileNames,
) async {
  final loader = FontLoader(family);
  var found = false;
  for (final name in fileNames) {
    final file = File('${fonts.path}/$name');
    if (!file.existsSync()) continue;
    found = true;
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
    );
  }
  if (!found) {
    throw StateError('No font files found for $family in ${fonts.path}');
  }
  await loader.load();
}

Directory? _materialFontsDirectory() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/artifacts/material_fonts');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  return null;
}
