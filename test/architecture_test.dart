import 'dart:convert';
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

    test('no dependency injects a permission into the release manifest', () {
      // The check above reads only this app's own manifest, and a dependency
      // can add a permission of its own during Android's manifest merge --
      // which that check would never see. Section 6 makes the absence of
      // INTERNET the thing that keeps the no-network promise verifiable, so
      // the plugins have to be looked at too.
      final config = File('.dart_tool/package_config.json');
      expect(
        config.existsSync(),
        isTrue,
        reason: 'run flutter pub get before this suite',
      );

      final packages =
          (jsonDecode(config.readAsStringSync())
                  as Map<String, Object?>)['packages']!
              as List<Object?>;

      final offenders = <String>[];
      for (final entry in packages.cast<Map<String, Object?>>()) {
        // Two things bite here, and both make this check silently pass while
        // looking at nothing. A rootUri has no trailing slash, so resolving
        // against it drops the package directory; and it may be relative, in
        // which case it is relative to package_config.json rather than to the
        // working directory.
        final rawRoot = entry['rootUri']! as String;
        final root = config.absolute.uri.resolve(
          rawRoot.endsWith('/') ? rawRoot : '$rawRoot/',
        );
        final manifest = File.fromUri(
          root.resolve('android/src/main/AndroidManifest.xml'),
        );
        if (!manifest.existsSync()) continue;

        final declared = RegExp(r'android\.permission\.[A-Z_]+')
            .allMatches(manifest.readAsStringSync())
            .map((m) => m[0]!)
            .toSet();
        if (declared.isNotEmpty) {
          offenders.add('${entry['name']}: ${declared.join(', ')}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'a dependency declares an Android permission this app never asked '
            'for. If it is INTERNET, remove the dependency rather than the '
            'permission; anything else needs a deliberate decision.',
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

  group('encryption at rest (CLAUDE.md section 6)', () {
    // This guard used to assert that sqlcipher_flutter_libs was a dependency,
    // which was exactly backwards. sqlite3 3.x loads its native library through
    // Dart build hooks and never consults that package, so its presence proved
    // nothing while its absence looked like the bug. The database was being
    // written unencrypted and every check here passed.
    //
    // What actually decides it is the hooks.user_defines block in pubspec.yaml.
    // open_database_test.dart proves the result end to end by reopening a
    // written file without the key; this only catches the configuration
    // regressing, quickly and without touching the disk.
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('an encrypting build of SQLite is selected', () {
      final hooks = RegExp(
        r'hooks:\s*\n\s*user_defines:\s*\n\s*sqlite3:\s*\n\s*source:\s*(\w+)',
      ).firstMatch(pubspec);

      expect(
        hooks,
        isNotNull,
        reason:
            'without hooks.user_defines the app bundles plain SQLite, '
            'PRAGMA key is a silent no-op, and the database is written in the '
            'clear while behaving completely normally',
      );
      expect(
        hooks!.group(1),
        anyOf('sqlite3mc', 'sqlcipher'),
        reason:
            'only these two sources support encryption; "sqlite3" is the '
            'plain build',
      );
    });

    test('no inert encryption plugin is depended on', () {
      // Adding either back would look like encryption while doing nothing,
      // which is worse than not having it: it invites the false assumption.
      for (final obsolete in const [
        'sqlcipher_flutter_libs',
        'sqlite3_flutter_libs',
      ]) {
        expect(
          pubspec,
          isNot(contains('$obsolete:')),
          reason:
              'sqlite3 3.x does not consult $obsolete; encryption comes '
              'from hooks.user_defines instead',
        );
      }
    });
  });
}
