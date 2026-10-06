import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the database encryption key.
///
/// An interface rather than a direct call to storage so that the choice of
/// backing package stays swappable and nothing else in the codebase depends on
/// it. Section 6's allowlist has no way to store a secret -- `local_auth` only
/// prompts -- so `flutter_secure_storage` was added specifically for this, and
/// keeping it behind one interface keeps that decision revisitable.
abstract class DatabaseKeyStore {
  /// The database key, creating and storing one on first use.
  ///
  /// Returns the same key on every later call: the database cannot be read
  /// without it and there is no cloud backup, so losing it means losing the
  /// user's data outright.
  Future<String> readOrCreateKey();

  /// Forgets the key.
  ///
  /// Only meaningful alongside deleting the database itself -- section 9's
  /// "delete all data" -- since without the key the file is unreadable anyway.
  Future<void> deleteKey();
}

/// A [DatabaseKeyStore] backed by the Android Keystore and the iOS Keychain.
class SecureDatabaseKeyStore implements DatabaseKeyStore {
  /// Creates the key store.
  ///
  /// [storage] is injectable so tests can exercise the generate-once behaviour
  /// without a platform channel.
  SecureDatabaseKeyStore({FlutterSecureStorage? storage, Random? random})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          ),
      _random = random ?? Random.secure();

  /// The key under which the database key is stored.
  static const storageKey = 'db_key_v1';

  /// Key length in bytes. 256 bits, matching SQLCipher's default cipher.
  static const keyLengthBytes = 32;

  final FlutterSecureStorage _storage;
  final Random _random;

  @override
  Future<String> readOrCreateKey() async {
    final existing = await _storage.read(key: storageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = _generateKey();
    await _storage.write(key: storageKey, value: created);
    return created;
  }

  @override
  Future<void> deleteKey() => _storage.delete(key: storageKey);

  /// A fresh key as lowercase hex.
  ///
  /// Generated, never derived from anything the user types: section 9 makes the
  /// PIN optional, so a passphrase-derived key would leave users without a PIN
  /// unencrypted. Hex rather than raw bytes so it survives being passed through
  /// a SQL pragma unaltered.
  String _generateKey() {
    final bytes = List<int>.generate(
      keyLengthBytes,
      (_) => _random.nextInt(256),
    );
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Escapes [key] for use in `PRAGMA key`.
///
/// The key is generated hex so it cannot contain a quote today, but building SQL
/// by concatenation without escaping is a habit worth not forming, and a future
/// key format might not be so tidy.
String pragmaKeyStatement(String key) {
  final escaped = key.replaceAll("'", "''");
  return "PRAGMA key = '$escaped'";
}

/// Never log or serialise the key. This exists to make that explicit at the
/// call site rather than relying on nobody being curious.
extension DatabaseKeySafety on String {
  /// A redacted form safe to appear in an error message.
  String get redactedKey => '<${utf8.encode(this).length} byte key, redacted>';
}
