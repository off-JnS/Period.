import 'package:period/data/database/open_database.dart';
import 'package:test/test.dart';

/// Tests for the guard that refuses to run against a plain sqlite3.
///
/// CLAUDE.md section 6 describes the failure being guarded against: both a plain
/// and an encrypted sqlite3 can end up linked, the plain one can win, and the
/// result is an unencrypted database that behaves completely normally. Nothing
/// fails and nothing warns. A silent failure needs a check that runs, which is
/// what these cover -- without a device, a plugin or a native library.
void main() {
  group('verifyCipherIsActive', () {
    test('accepts a connection that reports a cipher and decrypts', () {
      expect(
        () => verifyCipherIsActive(
          cipherVersion: () => '4.10.0 community',
          readSchemaVersion: () => 1,
        ),
        returnsNormally,
      );
    });

    test('rejects a plain sqlite3, which reports no cipher at all', () {
      // The exact shape of the failure this exists for: PRAGMA cipher_version
      // returns an empty result set on a build that is not SQLCipher, so the
      // database would be written in the clear while looking completely fine.
      expect(
        () => verifyCipherIsActive(
          cipherVersion: () => null,
          readSchemaVersion: () => 1,
        ),
        throwsA(isA<DatabaseNotEncrypted>()),
      );
    });

    test('rejects an empty cipher version, not just a missing one', () {
      expect(
        () => verifyCipherIsActive(
          cipherVersion: () => '',
          readSchemaVersion: () => 1,
        ),
        throwsA(isA<DatabaseNotEncrypted>()),
      );
    });

    test('rejects a connection where asking for the cipher throws', () {
      expect(
        () => verifyCipherIsActive(
          cipherVersion: () => throw StateError('no such pragma'),
          readSchemaVersion: () => 1,
        ),
        throwsA(isA<DatabaseNotEncrypted>()),
      );
    });

    test('rejects a cipher build whose header will not decrypt', () {
      // SQLCipher is linked, so the version reads back, but the key is wrong or
      // missing and the header cannot be read. Surfacing it here means the app
      // refuses to start rather than failing partway through a later write.
      expect(
        () => verifyCipherIsActive(
          cipherVersion: () => '4.10.0 community',
          readSchemaVersion: () => throw StateError('file is not a database'),
        ),
        throwsA(isA<DatabaseNotEncrypted>()),
      );
    });

    test('checks the cipher before trying to read the header', () {
      // Order matters for the diagnostic: on a plain sqlite3 the header read
      // would succeed, so checking it first would report "fine" about a
      // database that is not encrypted at all.
      var readHeader = false;
      expect(
        () => verifyCipherIsActive(
          cipherVersion: () => null,
          readSchemaVersion: () {
            readHeader = true;
            return 1;
          },
        ),
        throwsA(isA<DatabaseNotEncrypted>()),
      );
      expect(readHeader, isFalse);
    });

    test('says what was wrong, without quoting the key', () {
      // The message reaches logs and crash reports. Section 6 keeps the key out
      // of everything, so the detail describes the condition and nothing else.
      Object? caught;
      try {
        verifyCipherIsActive(
          cipherVersion: () => null,
          readSchemaVersion: () => 1,
        );
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<DatabaseNotEncrypted>());
      expect('$caught', contains('SQLCipher'));
    });
  });
}
