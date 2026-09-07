import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
import 'package:period/presentation/lock/lock_gate.dart';
import 'package:period/presentation/lock/lock_screen.dart';
import 'package:period/presentation/providers.dart';

import '../support/app_lock.dart';
import '../support/database.dart';
import '../support/widgets.dart';

/// Section 9's optional lock.
///
/// The test that carries the actual privacy claim is "the app is not built
/// behind the lock". A lock screen drawn on top of a live app is theatre: the
/// content is still in the tree, still laid out, and one stray hit test from
/// being reachable.
///
/// The test that carries the safety claim is the opposite one -- a device that
/// cannot authenticate must open the app, not trap her out of her own health
/// data.
void main() {
  late AppDatabase db;
  late FakeAppLock lock;

  setUp(() {
    db = aDatabase();
    lock = FakeAppLock();
  });

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(db),
    appLockProvider.overrideWithValue(lock),
  ];

  /// The thing behind the gate. A plain widget rather than the real shell, so
  /// these tests are about the gate and nothing else.
  const guarded = Text('her entries', textDirection: TextDirection.ltr);

  Future<void> pumpGate(WidgetTester tester, {required bool enabled}) async {
    if (enabled) {
      await db.settingsDao.writeAppLockEnabled(enabled: true);
    }
    await pumpWithDatabase(
      tester,
      const LockGate(child: Scaffold(body: guarded)),
      database: db,
      overrides: overrides(),
    );
  }

  /// Walks the real transition path. Flutter rejects a jump straight from
  /// resumed to paused, and so does a phone: the states in between are where a
  /// naive gate either misses the moment or fires constantly.
  Future<void> background(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settleDatabase(tester);
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settleDatabase(tester);
  }

  /// The provider container behind the pumped tree.
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LockGate)));

  Future<void> sendLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await settleDatabase(tester);
  }

  group('when the lock is off', () {
    testWidgets('the app opens without a prompt', (tester) async {
      await pumpGate(tester, enabled: false);

      expect(find.text('her entries'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
      expect(lock.prompts, 0);
    });

    testWidgets('backgrounding does not lock it', (tester) async {
      await pumpGate(tester, enabled: false);

      await background(tester);
      await foreground(tester);

      expect(find.text('her entries'), findsOneWidget);
      expect(lock.prompts, 0);
    });
  });

  group('when the lock is on', () {
    testWidgets('it asks on cold start and opens when she passes', (
      tester,
    ) async {
      await pumpGate(tester, enabled: true);

      expect(lock.prompts, 1);
      expect(find.text('her entries'), findsOneWidget);
    });

    testWidgets('the app is not built behind the lock', (tester) async {
      // The claim the whole feature rests on. Not "is it covered" -- is it
      // there at all.
      lock.accepts = false;
      await pumpGate(tester, enabled: true);

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('her entries'), findsNothing);
    });

    testWidgets('a refusal leaves it locked, and she can try again', (
      tester,
    ) async {
      lock.accepts = false;
      await pumpGate(tester, enabled: true);
      expect(find.byType(LockScreen), findsOneWidget);

      lock.accepts = true;
      await tester.tap(find.text('Unlock'));
      await settleDatabase(tester);

      expect(find.text('her entries'), findsOneWidget);
      expect(lock.prompts, 2);
    });

    testWidgets('the prompt says nothing about cycles', (tester) async {
      // It appears on a screen anyone nearby can see, so it is held to the
      // same rule as notification text.
      await pumpGate(tester, enabled: true);

      expect(lock.lastReason, 'Unlock to continue');
      for (final word in ['period', 'cycle', 'fertile', 'pregnan']) {
        expect(
          lock.lastReason!.toLowerCase(),
          isNot(contains(word)),
          reason: 'the lock prompt must not say "$word"',
        );
      }
    });

    testWidgets('the first frame after resuming is the lock, not her data', (
      tester,
    ) async {
      await pumpGate(tester, enabled: true);
      expect(find.text('her entries'), findsOneWidget);

      // The flag flips on the way out rather than on the way back, which is
      // the whole point: a paused app renders nothing, so by flipping while it
      // is away there is no frame of real content for the first rebuild to
      // show. The assertion has to be made after resuming because that is when
      // frames start again -- and a refused prompt is what proves the lock
      // held rather than the unlock being what cleared it.
      lock.accepts = false;
      await background(tester);
      await foreground(tester);

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('her entries'), findsNothing);
    });

    testWidgets('it asks again on resume', (tester) async {
      await pumpGate(tester, enabled: true);
      await background(tester);
      await foreground(tester);

      expect(lock.prompts, 2);
      expect(find.text('her entries'), findsOneWidget);
    });

    testWidgets('inactive alone does not lock it', (tester) async {
      // A notification shade pulled halfway down, a call banner. Locking on
      // every inactive would fire constantly.
      await pumpGate(tester, enabled: true);

      await sendLifecycle(tester, AppLifecycleState.inactive);

      expect(find.text('her entries'), findsOneWidget);
      expect(lock.prompts, 1);
    });
  });

  group('the setting reaches the gate without a restart', () {
    testWidgets('turning it off unlocks immediately', (tester) async {
      await pumpGate(tester, enabled: true);
      expect(find.text('her entries'), findsOneWidget);

      lock.accepts = false;
      await background(tester);
      await foreground(tester);
      expect(find.byType(LockScreen), findsOneWidget);

      // Not reachable from behind the lock in the real app, but a restore can
      // change it, and a gate that cached the flag would keep locking for the
      // rest of the session against a setting that says otherwise.
      await db.settingsDao.writeAppLockEnabled(enabled: false);
      container(tester).invalidate(settingsProvider);
      await settleDatabase(tester);

      expect(find.text('her entries'), findsOneWidget);
    });

    testWidgets('turning it on locks the next time the app goes away', (
      tester,
    ) async {
      await pumpGate(tester, enabled: false);
      expect(find.text('her entries'), findsOneWidget);

      await db.settingsDao.writeAppLockEnabled(enabled: true);
      container(tester).invalidate(settingsProvider);
      await settleDatabase(tester);

      // Not prompted on the spot: she is looking at settings, and an
      // unprovoked prompt mid-toggle is jarring. It takes effect where it
      // matters.
      expect(find.text('her entries'), findsOneWidget);

      lock.accepts = false;
      await background(tester);
      await foreground(tester);
      expect(find.byType(LockScreen), findsOneWidget);
    });
  });

  group('the failure modes that matter', () {
    testWidgets('a phone that cannot authenticate opens the app', (
      tester,
    ) async {
      // She turned the lock on, then removed her phone's passcode. Waiting for
      // an authentication that can never succeed would lock her out of her own
      // health data permanently -- the failure section 1 ranks alongside a
      // leak.
      lock
        ..available = false
        ..accepts = false;

      await pumpGate(tester, enabled: true);

      expect(find.text('her entries'), findsOneWidget);
      expect(lock.prompts, 0, reason: 'there was nothing to prompt with');
    });

    testWidgets(
      'an unreadable settings row opens the app rather than bricking',
      (tester) async {
        // SettingsDao throws on a cycle mode this build cannot read -- from a
        // newer build, or a corrupt row. Staying locked would mean she could
        // never reach the screen that explains it, or the delete-everything
        // button. An app that cannot be opened is data that has been erased.
        await db.settingsDao.writeAppLockEnabled(enabled: true);
        await db.customStatement(
          'INSERT INTO settings (key, value) VALUES (?, ?)',
          ['cycle_mode', 'a_mode_from_the_future'],
        );

        await pumpWithDatabase(
          tester,
          const LockGate(child: Scaffold(body: guarded)),
          database: db,
          overrides: overrides(),
        );

        expect(find.text('her entries'), findsOneWidget);
      },
    );

    testWidgets('a refusal does not re-prompt when the sheet hands back focus', (
      tester,
    ) async {
      // The device's own prompt resigns the app active and delivers a resumed
      // when it closes. Re-prompting on every resume means cancelling raises
      // another prompt at once, and again, with no way out but force-quitting.
      lock.accepts = false;
      await pumpGate(tester, enabled: true);
      expect(lock.prompts, 1);

      await sendLifecycle(tester, AppLifecycleState.inactive);
      await sendLifecycle(tester, AppLifecycleState.resumed);

      expect(
        lock.prompts,
        1,
        reason: 'the dismissed sheet re-triggered its own prompt',
      );
      expect(find.byType(LockScreen), findsOneWidget);
    });

    testWidgets('the lifecycle churn of its own prompt does not loop', (
      tester,
    ) async {
      // On iOS the system sheet drives the app to inactive and then paused. A
      // gate that re-locked on that would re-lock during its own prompt, and
      // prompt again, forever.
      await db.settingsDao.writeAppLockEnabled(enabled: true);

      var promptsDuringAuth = 0;
      final slowLock = _SlowLock(
        onAuthenticate: (tester) async {
          promptsDuringAuth++;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        },
        tester: tester,
      );

      await pumpWithDatabase(
        tester,
        const LockGate(child: Scaffold(body: guarded)),
        database: db,
        overrides: [
          databaseProvider.overrideWithValue(db),
          appLockProvider.overrideWithValue(slowLock),
        ],
      );

      expect(promptsDuringAuth, 1, reason: 'the prompt re-entered itself');
      expect(find.text('her entries'), findsOneWidget);
    });
  });
}

/// A lock that shakes the app's lifecycle while its prompt is up, the way the
/// real system sheet does on iOS.
class _SlowLock implements FakeAppLock {
  _SlowLock({required this.onAuthenticate, required this.tester});

  final Future<void> Function(WidgetTester tester) onAuthenticate;
  final WidgetTester tester;

  @override
  bool available = true;

  @override
  bool accepts = true;

  @override
  int prompts = 0;

  @override
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    lastReason = reason;
    await onAuthenticate(tester);
    return accepts;
  }
}
