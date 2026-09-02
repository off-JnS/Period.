import 'dart:io';

import 'package:test/test.dart';

/// Turns two CLAUDE.md rules into checks that run, rather than conventions that
/// are remembered. Both describe promises to the user, not house style: the
/// first keeps cycle days free of timestamps, the second is what makes "this app
/// makes no network requests" verifiable instead of merely asserted.
void main() {
  group('domain layer purity (CLAUDE.md sections 2 and 3)', () {
    final domainFiles = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    test('there are domain files to check', () {
      // Without this the group would pass vacuously if the directory moved.
      expect(domainFiles, isNotEmpty);
    });

    // Section 2 forbids the domain importing "flutter, drift, or any plugin".
    // This check started out stricter than that -- it allowed no package: import
    // at all -- which turned out to be stricter than the rules intend: section 6
    // allowlists freezed, and the domain models are exactly what freezed is for.
    //
    // So the rule here is an allowlist rather than a blanket ban. What earns a
    // place on it: pure Dart, no Flutter binding, no platform channel, no I/O.
    // An annotation package qualifies. drift does not, because it reaches the
    // database. Anything not named here is still refused.
    const allowedPackages = {'freezed_annotation'};

    test(
      'imports only the Dart core libraries and allowlisted annotations',
      () {
        final offenders = <String>[];
        for (final file in domainFiles) {
          for (final line in file.readAsLinesSync()) {
            final match = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''')
                .firstMatch(line);
            if (match == null) continue;
            final uri = match.group(1)!;

            // Relative imports within the domain are fine.
            if (!uri.startsWith('package:') && !uri.startsWith('dart:')) {
              continue;
            }

            if (uri.startsWith('package:')) {
              final package = uri.substring('package:'.length).split('/').first;
              if (allowedPackages.contains(package)) {
                continue;
              }
            }
            offenders.add('${file.path}: $uri');
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'the domain depends on nothing but Dart and the allowlist. Move '
              'the logic, do not add the import. Offending imports:\n'
              '${offenders.join('\n')}',
        );
      },
    );

    test('the allowlist itself stays small and pure', () {
      // A guard on the guard. Widening the allowlist should be a deliberate act
      // with a reason, not something that accretes; anything that reaches
      // Flutter, a plugin or the database must never appear here.
      expect(
        allowedPackages,
        everyElement(
          isNot(
            anyOf(
              contains('flutter'),
              contains('drift'),
              contains('sqlite'),
              contains('sqlcipher'),
              contains('path_provider'),
              contains('secure_storage'),
            ),
          ),
        ),
      );
      expect(allowedPackages, hasLength(lessThanOrEqualTo(3)));
    });

    test('mentions no DateTime, Duration or epoch timestamp', () {
      final forbidden = {
        'DateTime': 'a cycle day is a calendar day, not a point in time',
        'Duration': 'use CycleDate.addDays, which cannot skip a day',
        'millisecondsSinceEpoch':
            'never persist an epoch value for a cycle day',
        'microsecondsSinceEpoch':
            'never persist an epoch value for a cycle day',
      };
      final offenders = <String>[];
      for (final file in domainFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Doc comments explain why these types are absent, so they are allowed
          // to name them.
          if (line.trimLeft().startsWith('//')) continue;
          for (final entry in forbidden.entries) {
            if (line.contains(entry.key)) {
              offenders.add(
                '${file.path}:${i + 1}: ${entry.key} — ${entry.value}',
              );
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'CLAUDE.md section 3. Offending lines:\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('no network (CLAUDE.md section 6)', () {
    test('the release manifest does not request INTERNET', () {
      // src/main is the only manifest merged into a release build, so this is
      // the one that decides whether a shipped APK can open a socket at all.
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      expect(
        manifest.existsSync(),
        isTrue,
        reason: 'the release manifest has moved; this check must follow it',
      );
      expect(
        manifest.readAsStringSync(),
        isNot(contains('android.permission.INTERNET')),
        reason:
            'if a build breaks because something wants INTERNET, remove the '
            'dependency rather than the permission',
      );
    });

    test('no runtime dependency is an HTTP or socket client', () {
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final runtimeDependencies = <String>[];
      var inDependencies = false;
      for (final line in pubspec) {
        if (line.startsWith('dependencies:')) {
          inDependencies = true;
          continue;
        }
        // Any other unindented key ends the runtime dependency block, which is
        // what keeps dev_dependencies out of this check.
        if (inDependencies &&
            line.isNotEmpty &&
            !line.startsWith(' ') &&
            !line.startsWith('#')) {
          inDependencies = false;
        }
        if (!inDependencies) continue;
        final match = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
        if (match != null) runtimeDependencies.add(match.group(1)!);
      }

      expect(
        runtimeDependencies,
        isNotEmpty,
        reason: 'failed to parse the dependencies block',
      );

      const banned = {
        'http',
        'dio',
        'web_socket_channel',
        'grpc',
        'firebase_core',
        'firebase_analytics',
        'firebase_crashlytics',
        'sentry',
        'sentry_flutter',
        'purchases_flutter',
        'google_mobile_ads',
      };
      expect(
        runtimeDependencies.toSet().intersection(banned),
        isEmpty,
        reason: 'CLAUDE.md section 6 forbids these without exception',
      );
    });
  });
}
