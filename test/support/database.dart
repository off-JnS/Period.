import 'package:drift/native.dart';
import 'package:period/data/database/database.dart';

/// An empty in-memory database, per test.
///
/// Note this is plain sqlite3, not SQLCipher: these tests exercise the schema
/// and the queries, never the encryption. Nothing here can prove the shipped
/// database is actually encrypted -- that needs a device build.
AppDatabase aDatabase() => AppDatabase(NativeDatabase.memory());
