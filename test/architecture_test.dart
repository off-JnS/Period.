import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Turns two CLAUDE.md rules into checks that run, rather than conventions that
/// are remembered. Both describe promises to the user, not house style: the
/// first keeps cycle days free of timestamps, the second is what makes "this app
/// makes no network requests" verifiable instead of merely asserted.
/// Permissions a dependency may declare, each one looked at and accepted.
///
/// Not a formality. Every entry widens what a shipped build can do, so a new
/// permission fails the test above until someone has read what it is for and
/// written it down here.
const acknowledgedPermissions = <String, Set<String>>{
  // Section 9's optional app lock. It lets the app ask Android to run its own
  // biometric prompt; it grants no access to data, to the network, or to
  // anything the app could not already reach.
  'local_auth_android': {'android.permission.USE_BIOMETRIC'},
};

/// Permissions that can never be acknowledged, because they are the promise.
///
/// Section 6 makes the absence of INTERNET what makes "this app makes no
/// network requests" checkable rather than merely stated.
const _networkPermissions = <String>{
  'android.permission.INTERNET',
  'android.permission.ACCESS_NETWORK_STATE',
  'android.permission.ACCESS_WIFI_STATE',
};

/// Source with its `//` comments removed.
///
/// Every platform check below was matching prose rather than code: the comments
/// explaining why FLAG_SECURE matters contain the words "FLAG_SECURE", so
/// deleting the call left the guard green. A check satisfied by its own
/// explanation is worse than none, because it is counted as coverage.
String codeOnly(String source) => source
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment == -1 ? line : line.substring(0, comment);
    })
    .join('\n');

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

  group('screenshot protection (CLAUDE.md section 9)', () {
    // None of this can be executed here. `flutter build ios --no-codesign`
    // proves only that it compiles, and no widget test can ask the operating
    // system what it put in the app switcher. What these checks buy is that the
    // code is present and the right shape -- the same technique that now guards
    // the two lockout bugs a review found in these exact files, both of which
    // were invisible to the whole suite and to CI.

    test('Android sets FLAG_SECURE, before the first frame', () {
      final activity = codeOnly(
        File('android/app/src/main/kotlin/app/period/MainActivity.kt')
            .readAsStringSync(),
      );

      expect(
        activity,
        contains('window.setFlags('),
        reason: 'nothing blanks the app-switcher thumbnail',
      );
      expect(activity, contains('WindowManager.LayoutParams.FLAG_SECURE'));
      // In onCreate rather than later: anywhere else leaves a window between
      // launch and protection.
      expect(
        activity.indexOf('onCreate'),
        lessThan(activity.indexOf('FLAG_SECURE')),
        reason: 'FLAG_SECURE must be set in onCreate',
      );
    });

    test('iOS covers the window when the app resigns active', () {
      final delegate = codeOnly(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      );

      expect(
        delegate,
        contains('override func applicationWillResignActive'),
        reason: 'nothing covers the window before the snapshot is taken',
      );
      expect(
        delegate,
        contains('UIBlurEffect'),
        reason: 'section 9 asks for a blur overlay',
      );
    });

    test('iOS hooks resign-active, not did-enter-background', () {
      // The snapshot is taken as the app resigns active. A cover added in
      // didEnterBackground arrives after the picture has been taken: it
      // compiles, runs, looks right in every log, and protects nothing. That
      // is the exact class of bug this file exists to catch.
      final delegate = codeOnly(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      );

      expect(
        delegate,
        isNot(contains('applicationDidEnterBackground')),
        reason:
            'covering on didEnterBackground is too late -- the app switcher '
            'already has its picture',
      );
    });

    test('iOS removes the cover again', () {
      // A cover added and never removed is its own lockout: the app running
      // normally behind a blur that nothing clears.
      final delegate = codeOnly(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      );

      expect(delegate, contains('override func applicationDidBecomeActive'));
      expect(
        delegate,
        contains('removeFromSuperview'),
        reason: 'the cover is never taken down',
      );
    });
  });

  group('the app lock cannot lock her out (CLAUDE.md section 9)', () {
    // Both of these are permanent-lockout bugs, and neither is visible from
    // Dart: the plugin reports the device as perfectly capable of
    // authenticating, then fails in a way that looks like a refusal. There is
    // no backup and no recovery path, so an unopenable app is an erased one.
    //
    // Neither is caught by `flutter build ios --no-codesign` or by any widget
    // test, which is why they are pinned here as text.

    test('the Android activity is a FragmentActivity', () {
      // local_auth_android refuses anything else and returns an error the Dart
      // side cannot tell apart from "she declined", so a plain FlutterActivity
      // means every unlock fails forever.
      final activity = File(
        'android/app/src/main/kotlin/app/period/MainActivity.kt',
      );
      expect(
        activity.existsSync(),
        isTrue,
        reason: 'the activity has moved; this check must follow it',
      );
      expect(
        codeOnly(activity.readAsStringSync()),
        contains(': FlutterFragmentActivity'),
        reason:
            'local_auth needs a FragmentActivity. With FlutterActivity the app '
            'lock refuses every unlock and her data is unreachable.',
      );
    });

    test('iOS declares why it uses Face ID', () {
      // iOS terminates the process on the first Face ID prompt when the
      // purpose string is absent. The lock resolves before any screen is
      // reachable, so she could never get back into settings to turn it off.
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        contains('NSFaceIDUsageDescription'),
        reason: 'iOS kills the app on its first Face ID prompt without this',
      );
      // Held to the same rule as notification text: it appears on a screen
      // anyone nearby can read.
      final reason = RegExp(
        r'<key>NSFaceIDUsageDescription</key>\s*<string>([^<]*)</string>',
      ).firstMatch(plist)?.group(1);
      expect(reason, isNotNull, reason: 'the key has no string beside it');
      for (final word in ['period', 'cycle', 'fertile', 'pregnan']) {
        expect(
          reason!.toLowerCase(),
          isNot(contains(word)),
          reason: 'the Face ID prompt must not mention "$word"',
        );
      }
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
      //
      // Two different rules apply. INTERNET can never be acknowledged: it is
      // the promise. Anything else is a decision someone has to make and
      // record, which is what acknowledgedPermissions is -- a new permission
      // fails this test until a person has looked at it and written down why
      // it is acceptable.
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

      final unacknowledged = <String>[];
      final networkPermissions = <String>[];
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

        final name = entry['name']! as String;
        final declared = RegExp(r'android\.permission\.[A-Z_]+')
            .allMatches(manifest.readAsStringSync())
            .map((m) => m[0]!)
            .toSet();

        for (final permission in declared) {
          if (_networkPermissions.contains(permission)) {
            networkPermissions.add('$name: $permission');
          } else if (!(acknowledgedPermissions[name] ?? const {}).contains(
            permission,
          )) {
            unacknowledged.add('$name: $permission');
          }
        }
      }

      expect(
        networkPermissions,
        isEmpty,
        reason:
            'a dependency wants network access. Section 6 is explicit: remove '
            'the dependency rather than the permission.',
      );
      expect(
        unacknowledged,
        isEmpty,
        reason:
            'a dependency declares an Android permission nobody has signed off '
            'on. Read what it is for, then add it to acknowledgedPermissions '
            'with a comment -- or drop the dependency.',
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
