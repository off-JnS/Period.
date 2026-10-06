import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:period/data/database_key_store.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage storage;
  late SecureDatabaseKeyStore keyStore;

  setUp(() {
    storage = _MockSecureStorage();
    keyStore = SecureDatabaseKeyStore(storage: storage);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  });

  group('reading the key', () {
    test('returns the stored key when one exists', () async {
      when(() => storage.read(key: SecureDatabaseKeyStore.storageKey))
          .thenAnswer((_) async => 'deadbeef');

      expect(await keyStore.readOrCreateKey(), 'deadbeef');
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    });

    test('generates and stores a key on first use', () async {
      when(() => storage.read(key: SecureDatabaseKeyStore.storageKey))
          .thenAnswer((_) async => null);

      final created = await keyStore.readOrCreateKey();

      final written = verify(
        () => storage.write(
          key: SecureDatabaseKeyStore.storageKey,
          value: captureAny(named: 'value'),
        ),
      ).captured.single;
      expect(written, created, reason: 'must store exactly what it returns');
    });

    test('treats an empty stored value as absent', () async {
      // A blank key would open an unencrypted database that looks fine.
      when(() => storage.read(key: SecureDatabaseKeyStore.storageKey))
          .thenAnswer((_) async => '');

      expect(await keyStore.readOrCreateKey(), isNotEmpty);
    });

    test('never derives the key from user input', () async {
      // Section 9 makes the PIN optional, so a passphrase-derived key would
      // leave users without a PIN unencrypted. Two fresh stores must not agree.
      when(() => storage.read(key: SecureDatabaseKeyStore.storageKey))
          .thenAnswer((_) async => null);

      final first = await keyStore.readOrCreateKey();
      final second = await SecureDatabaseKeyStore(storage: storage)
          .readOrCreateKey();
      expect(first, isNot(second));
    });
  });

  group('the generated key', () {
    late String key;

    setUp(() async {
      when(() => storage.read(key: SecureDatabaseKeyStore.storageKey))
          .thenAnswer((_) async => null);
      key = await keyStore.readOrCreateKey();
    });

    test('is 256 bits of hex', () {
      expect(key, hasLength(SecureDatabaseKeyStore.keyLengthBytes * 2));
      expect(key, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('keeps leading zero bytes rather than dropping them', () async {
      // A byte formatted without padding would silently shorten the key.
      final zeroes = SecureDatabaseKeyStore(
        storage: storage,
        random: _ZeroRandom(),
      );
      final allZero = await zeroes.readOrCreateKey();
      expect(allZero, '0' * (SecureDatabaseKeyStore.keyLengthBytes * 2));
    });
  });

  group('pragmaKeyStatement', () {
    test('wraps the key in quotes', () {
      expect(pragmaKeyStatement('abc123'), "PRAGMA key = 'abc123'");
    });

    test('escapes a quote rather than ending the statement early', () {
      expect(pragmaKeyStatement("a'b"), "PRAGMA key = 'a''b'");
    });
  });

  test('deleteKey forgets the stored key', () async {
    await keyStore.deleteKey();
    verify(() => storage.delete(key: SecureDatabaseKeyStore.storageKey))
        .called(1);
  });

  test('redactedKey never reveals the key', () {
    expect('deadbeef'.redactedKey, isNot(contains('deadbeef')));
    expect('deadbeef'.redactedKey, contains('redacted'));
  });
}

/// Always yields zero, to prove byte formatting pads.
class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}
