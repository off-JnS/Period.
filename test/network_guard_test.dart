import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// CLAUDE.md section 6 forbids HTTP clients, sockets and anything that phones
/// home. Some allowlisted packages still *depend* on one: `timezone` lists
/// `http` for its web-only data loader, so `http` appears in pubspec.lock even
/// though the app never uses it.
///
/// What protects the promise is not the lockfile but what the app can reach.
/// This walks every import and export, following conditional imports down
/// every branch, starting from lib/main.dart and through every package it
/// reaches, and fails if any forbidden package is among them. Code that is not
/// reachable from main is not compiled into the app.
///
/// The Android release manifest having no INTERNET permission is the second,
/// independent barrier.
void main() {
  const forbidden = {
    'http',
    'dio',
    'web_socket_channel',
    'grpc',
    'sqlite3_flutter_libs',
    'firebase_core',
    'firebase_analytics',
    'firebase_crashlytics',
    'sentry',
    'sentry_flutter',
    'purchases_flutter',
  };

  test('nothing the app imports can reach a network package', () {
    final packages = _packageRoots();
    expect(packages, contains('period'), reason: 'run `flutter pub get`');

    final reached = <String>{};
    final queue = <Uri>[Uri.parse('package:period/main.dart')];
    final seen = <String>{};
    final offenders = <String>[];
    var filesRead = 0;

    while (queue.isNotEmpty) {
      final uri = queue.removeLast();
      if (!seen.add(uri.toString())) continue;
      if (uri.scheme != 'package') continue;

      final package = uri.pathSegments.first;
      reached.add(package);
      // The Flutter SDK itself imports no network package and is large;
      // skipping it keeps this test fast.
      if (package == 'flutter' || package == 'sky_engine') continue;
      if (forbidden.contains(package)) {
        offenders.add(uri.toString());
        continue;
      }

      final root = packages[package];
      if (root == null) continue;
      final file = File.fromUri(
        root.resolve(uri.pathSegments.skip(1).join('/')),
      );
      if (!file.existsSync()) continue;
      filesRead++;

      for (final target in _directives(file.readAsStringSync())) {
        queue.add(uri.resolve(target));
      }
    }

    // Guards the guard: if paths stopped resolving, it would read nothing
    // and pass. The app and its packages are hundreds of files.
    expect(filesRead, greaterThan(200));
    expect(reached, containsAll(['period', 'timezone', 'drift']));
    expect(
      offenders,
      isEmpty,
      reason: 'the app can reach a forbidden package:\n${offenders.join('\n')}',
    );
  });

  test('the guard would catch a forbidden import', () {
    // A guard that never fires proves nothing. timezone's web loader is the
    // one place http is imported; reached directly, it must be caught.
    final source = File.fromUri(
      _packageRoots()['timezone']!.resolve('browser.dart'),
    ).readAsStringSync();
    expect(
      _directives(source).map(Uri.parse).map((u) => u.pathSegments.first),
      contains('http'),
    );
  });
}

/// Every import, export and conditional-import target in [source].
Iterable<String> _directives(String source) sync* {
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+([\s\S]*?);''',
    multiLine: true,
  );
  final quoted = RegExp(r'''['"]([^'"]+)['"]''');
  for (final match in directive.allMatches(source)) {
    for (final uri in quoted.allMatches(match.group(1)!)) {
      final value = uri.group(1)!;
      if (value.startsWith('dart:')) continue;
      yield value;
    }
  }
}

/// Package name to the root of its `lib/`, from .dart_tool/package_config.json.
Map<String, Uri> _packageRoots() {
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final base = configFile.absolute.uri;
  String dir(String path) => path.endsWith('/') ? path : '$path/';
  return {
    for (final entry in (config['packages'] as List).cast<Map>())
      entry['name'] as String: base
          .resolve(dir(entry['rootUri'] as String))
          .resolve(dir(entry['packageUri'] as String)),
  };
}
