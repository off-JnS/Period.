import 'package:period/data/database/database.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/models.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = aDatabase());
  tearDown(() => db.close());

  group('period starts', () {
    test('are empty to begin with', () async {
      // Section 7's first awkward case: no cycles at all.
      expect(await db.logDao.allPeriodStarts(), isEmpty);
    });

    test('come back oldest first however they went in', () async {
      // Entries logged out of order, per section 7.
      await db.logDao.addPeriodStart(aDate(2024, 3, 1));
      await db.logDao.addPeriodStart(aDate(2024, 1, 1));
      await db.logDao.addPeriodStart(aDate(2024, 2, 1));

      expect(await db.logDao.allPeriodStarts(), [
        aDate(2024, 1, 1),
        aDate(2024, 2, 1),
        aDate(2024, 3, 1),
      ]);
    });

    test('sort correctly across a year boundary', () async {
      // The reason dates are stored as zero-padded ISO text: it sorts
      // chronologically as a string, with no decoding.
      await db.logDao.addPeriodStart(aDate(2024, 1, 5));
      await db.logDao.addPeriodStart(aDate(2023, 12, 31));

      expect(await db.logDao.allPeriodStarts(), [
        aDate(2023, 12, 31),
        aDate(2024, 1, 5),
      ]);
    });

    test('marking the same day twice records it once', () async {
      await db.logDao.addPeriodStart(aDate(2024, 1, 1));
      await db.logDao.addPeriodStart(aDate(2024, 1, 1));

      expect(await db.logDao.allPeriodStarts(), hasLength(1));
    });

    test('a retroactive correction is a delete and an add', () async {
      // Section 4's design rests on this being cheap. Nothing derived is stored,
      // so moving a start date leaves nothing stale behind.
      await db.logDao.addPeriodStart(aDate(2024, 1, 3));
      await db.logDao.removePeriodStart(aDate(2024, 1, 3));
      await db.logDao.addPeriodStart(aDate(2024, 1, 1));

      expect(await db.logDao.allPeriodStarts(), [aDate(2024, 1, 1)]);
    });

    test('removing a day that was never marked is harmless', () async {
      await db.logDao.removePeriodStart(aDate(2024, 1, 1));
      expect(await db.logDao.allPeriodStarts(), isEmpty);
    });

    test('a three-month gap is stored as-is, not filled in', () async {
      await db.logDao.addPeriodStart(aDate(2024, 1, 1));
      await db.logDao.addPeriodStart(aDate(2024, 4, 1));

      expect(await db.logDao.allPeriodStarts(), hasLength(2));
    });
  });

  group('day entries', () {
    test('an unlogged day has no entry', () async {
      expect(await db.logDao.entryOn(aDate(2024, 5, 17)), isNull);
    });

    test('round-trip preserves every field', () async {
      final entry = aDayEntry(
        date: aDate(2024, 5, 17),
        flow: FlowIntensity.medium,
        note: 'sore back',
        symptoms: {
          aSymptom(key: 'cramps'),
          aSymptom(key: 'headache'),
        },
      );
      await db.logDao.saveEntry(entry);

      expect(await db.logDao.entryOn(aDate(2024, 5, 17)), entry);
    });

    test('a bare entry round-trips with its nulls intact', () async {
      // Section 5: null means "not recorded". It must not come back as none or
      // as an empty string.
      final bare = aDayEntry(date: aDate(2024, 5, 17));
      await db.logDao.saveEntry(bare);

      final loaded = await db.logDao.entryOn(aDate(2024, 5, 17));
      expect(loaded, isNotNull);
      expect(loaded!.flow, isNull);
      expect(loaded.note, isNull);
      expect(loaded.symptoms, isEmpty);
    });

    test('a recorded "none" is distinct from an unrecorded flow', () async {
      await db.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 17), flow: FlowIntensity.none),
      );
      await db.logDao.saveEntry(aDayEntry(date: aDate(2024, 5, 18)));

      expect(
        (await db.logDao.entryOn(aDate(2024, 5, 17)))!.flow,
        FlowIntensity.none,
      );
      expect((await db.logDao.entryOn(aDate(2024, 5, 18)))!.flow, isNull);
    });

    test('every flow value survives the database', () async {
      for (final flow in FlowIntensity.values) {
        await db.logDao.saveEntry(
          aDayEntry(date: aDate(2024, 5, 17), flow: flow),
        );
        expect((await db.logDao.entryOn(aDate(2024, 5, 17)))!.flow, flow);
      }
    });

    test('saving twice replaces rather than duplicates', () async {
      await db.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 17), note: 'first'),
      );
      await db.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 17), note: 'second'),
      );

      expect((await db.logDao.entryOn(aDate(2024, 5, 17)))!.note, 'second');
    });

    test('clearing a note actually clears it', () async {
      await db.logDao.saveEntry(
        aDayEntry(date: aDate(2024, 5, 17), note: 'written in error'),
      );
      await db.logDao.saveEntry(aDayEntry(date: aDate(2024, 5, 17)));

      expect((await db.logDao.entryOn(aDate(2024, 5, 17)))!.note, isNull);
    });

    test('removing a symptom removes it', () async {
      final date = aDate(2024, 5, 17);
      await db.logDao.saveEntry(
        aDayEntry(
          date: date,
          symptoms: {
            aSymptom(key: 'cramps'),
            aSymptom(key: 'headache'),
          },
        ),
      );
      await db.logDao.saveEntry(
        aDayEntry(
          date: date,
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );

      expect((await db.logDao.entryOn(date))!.symptoms, {
        aSymptom(key: 'cramps'),
      });
    });

    test('a day with only symptoms is still a logged day', () async {
      final date = aDate(2024, 5, 17);
      await db.logDao.saveEntry(
        aDayEntry(
          date: date,
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );

      final loaded = await db.logDao.entryOn(date);
      expect(loaded, isNotNull);
      expect(loaded!.symptoms, hasLength(1));
    });

    test('a symptom nobody anticipated needs no schema change', () async {
      // Section 5's reason for a string-keyed many-to-many.
      const invented = 'restless-legs';
      await db.logDao.saveEntry(
        aDayEntry(
          date: aDate(2024, 5, 17),
          symptoms: {aSymptom(key: invented)},
        ),
      );

      expect((await db.logDao.entryOn(aDate(2024, 5, 17)))!.symptoms, {
        aSymptom(key: invented),
      });
    });

    test('deleting an entry removes its symptoms too', () async {
      final date = aDate(2024, 5, 17);
      await db.logDao.saveEntry(
        aDayEntry(
          date: date,
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );
      await db.logDao.deleteEntry(date);

      expect(await db.logDao.entryOn(date), isNull);
    });
  });

  group('date ranges', () {
    setUp(() async {
      for (final day in [1, 5, 10, 20, 31]) {
        await db.logDao.saveEntry(
          aDayEntry(date: aDate(2024, 1, day), note: 'day $day'),
        );
      }
    });

    test('are inclusive at both ends', () async {
      final entries = await db.logDao.entriesBetween(
        aDate(2024, 1, 5),
        aDate(2024, 1, 20),
      );
      expect(entries.map((entry) => entry.date), [
        aDate(2024, 1, 5),
        aDate(2024, 1, 10),
        aDate(2024, 1, 20),
      ]);
    });

    test('return nothing for a range with no entries', () async {
      expect(
        await db.logDao.entriesBetween(aDate(2024, 2, 1), aDate(2024, 2, 29)),
        isEmpty,
      );
    });

    test('handle a single-day range', () async {
      final entries = await db.logDao.entriesBetween(
        aDate(2024, 1, 10),
        aDate(2024, 1, 10),
      );
      expect(entries, hasLength(1));
    });

    test('span a year boundary correctly', () async {
      await db.logDao.saveEntry(aDayEntry(date: aDate(2023, 12, 28)));
      final entries = await db.logDao.entriesBetween(
        aDate(2023, 12, 27),
        aDate(2024, 1, 2),
      );
      expect(entries.map((entry) => entry.date), [
        aDate(2023, 12, 28),
        aDate(2024, 1, 1),
      ]);
    });

    test('carry symptoms with each entry', () async {
      await db.logDao.saveEntry(
        aDayEntry(
          date: aDate(2024, 1, 10),
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );
      final entries = await db.logDao.entriesBetween(
        aDate(2024, 1, 10),
        aDate(2024, 1, 10),
      );
      expect(entries.single.symptoms, {aSymptom(key: 'cramps')});
    });
  });

  group('delete all data', () {
    test('leaves every table empty', () async {
      // Section 9: "delete all data" must actually delete.
      await db.logDao.addPeriodStart(aDate(2024, 1, 1));
      await db.logDao.saveEntry(
        aDayEntry(
          date: aDate(2024, 1, 1),
          note: 'something private',
          symptoms: {aSymptom(key: 'cramps')},
        ),
      );

      await db.logDao.deleteEverything();

      expect(await db.logDao.allPeriodStarts(), isEmpty);
      expect(await db.logDao.entryOn(aDate(2024, 1, 1)), isNull);
      for (final table in db.allTables) {
        expect(
          await db.select(table).get(),
          isEmpty,
          reason: '${table.actualTableName} still has rows',
        );
      }
    });
  });
}
