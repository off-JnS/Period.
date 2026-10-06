import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/lock/app_lock.dart';

import '../support/fake_authenticator.dart';

void main() {
  late FakeAuthenticator auth;
  late List<bool> saved;

  setUp(() {
    auth = FakeAuthenticator();
    saved = [];
  });

  AppLock lock({bool enabled = true}) => AppLock(
    authenticator: auth,
    enabled: enabled,
    save: ({required enabled}) async => saved.add(enabled),
  );

  group('on a cold start', () {
    test('starts locked when the lock is on', () {
      expect(lock().locked, isTrue);
    });

    test('starts open when the lock is off', () {
      expect(lock(enabled: false).locked, isFalse);
    });
  });

  group('leaving the app', () {
    test('locks it when the lock is on', () async {
      final l = lock();
      await l.unlock(reason: 'r');
      l.appHidden();
      expect(l.locked, isTrue);
    });

    test('does nothing when the lock is off', () {
      final l = lock(enabled: false)..appHidden();
      expect(l.locked, isFalse);
    });
  });

  group('unlocking', () {
    test('opens after a confirmed owner', () async {
      final l = lock();
      await l.unlock(reason: 'r');
      expect(l.locked, isFalse);
    });

    test('stays locked when cancelled or failed', () async {
      auth.succeeds = false;
      final l = lock();
      await l.unlock(reason: 'r');
      expect(l.locked, isTrue);
    });

    test('never stacks a second prompt on one already showing', () async {
      auth.pending = Completer<bool>();
      final l = lock();
      final first = l.unlock(reason: 'r');
      await l.unlock(reason: 'r');
      expect(auth.prompts, 1);
      expect(l.authenticating, isTrue);

      auth.pending!.complete(true);
      await first;
      expect(l.authenticating, isFalse);
      expect(l.locked, isFalse);
    });

    test('does not prompt when already open', () async {
      final l = lock(enabled: false);
      await l.unlock(reason: 'r');
      expect(auth.prompts, 0);
    });
  });

  group('turning the lock on', () {
    test('confirms the owner, then stores it', () async {
      final l = lock(enabled: false);
      expect(
        await l.setEnabled(enabled: true, reason: 'r'),
        LockChange.changed,
      );
      expect(auth.prompts, 1);
      expect(saved, [true]);
      expect(l.enabled, isTrue);
      // Turning it on does not lock her out of the screen she is on.
      expect(l.locked, isFalse);
    });

    test('is refused on a device with no passcode', () async {
      auth.available = false;
      final l = lock(enabled: false);
      expect(
        await l.setEnabled(enabled: true, reason: 'r'),
        LockChange.unavailable,
      );
      expect(auth.prompts, 0);
      expect(saved, isEmpty);
      expect(l.enabled, isFalse);
    });

    test('changes nothing when the confirmation fails', () async {
      auth.succeeds = false;
      final l = lock(enabled: false);
      expect(
        await l.setEnabled(enabled: true, reason: 'r'),
        LockChange.notConfirmed,
      );
      expect(saved, isEmpty);
      expect(l.enabled, isFalse);
    });
  });

  group('turning the lock off', () {
    test('needs the owner too', () async {
      final l = lock();
      await l.unlock(reason: 'r');
      auth.succeeds = false;
      expect(
        await l.setEnabled(enabled: false, reason: 'r'),
        LockChange.notConfirmed,
      );
      expect(l.enabled, isTrue);
      expect(saved, isEmpty);
    });

    test('stores it and leaves the app open', () async {
      final l = lock();
      await l.unlock(reason: 'r');
      expect(
        await l.setEnabled(enabled: false, reason: 'r'),
        LockChange.changed,
      );
      expect(saved, [false]);
      expect(l.locked, isFalse);
      l.appHidden();
      expect(l.locked, isFalse);
    });
  });

  group('confirmOwner', () {
    test('asks when the lock is on', () async {
      final l = lock();
      await l.unlock(reason: 'r');
      auth.succeeds = false;
      expect(await l.confirmOwner(reason: 'r'), isFalse);
      auth.succeeds = true;
      expect(await l.confirmOwner(reason: 'r'), isTrue);
    });

    test('passes without a prompt when the lock is off', () async {
      final l = lock(enabled: false);
      expect(await l.confirmOwner(reason: 'r'), isTrue);
      expect(auth.prompts, 0);
    });
  });
}
