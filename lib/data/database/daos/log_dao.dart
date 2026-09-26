import 'package:drift/drift.dart';

import '../../../domain/models/cycle_date.dart';
import '../../../domain/models/day_entry.dart';
import '../../../domain/models/symptom.dart';
import '../database.dart';
import '../tables.dart';

part 'log_dao.g.dart';

/// Reads and writes what the user logged.
///
/// Everything here returns stored facts. Nothing computes a cycle, a length or
/// a prediction -- section 4 does that on read, further up, from
/// [PeriodStarts].
@DriftAccessor(tables: [PeriodStarts, DayEntries, DaySymptoms])
class LogDao extends DatabaseAccessor<AppDatabase> with _$LogDaoMixin {
  /// Creates the accessor.
  LogDao(super.attachedDatabase);

  /// Every period start the user recorded, oldest first.
  Future<List<CycleDate>> allPeriodStarts() async {
    final rows = await (select(
      periodStarts,
    )..orderBy([(row) => OrderingTerm(expression: row.date)])).get();
    return rows.map((row) => row.date).toList();
  }

  /// Marks [date] as a period start. Marking the same day twice is harmless.
  Future<void> addPeriodStart(CycleDate date) async {
    await into(periodStarts).insert(
      PeriodStartsCompanion.insert(date: date),
      mode: InsertMode.replace,
    );
  }

  /// Unmarks [date] as a period start.
  ///
  /// Section 4's whole design rests on this being cheap: correcting a start date
  /// is something users do constantly, and nothing derived has to be rebuilt
  /// because nothing derived was stored.
  Future<void> removePeriodStart(CycleDate date) async {
    await (delete(
      periodStarts,
    )..where((row) => row.date.equals(date.toIso8601()))).go();
  }

  /// The entry for [date], or null if the user logged nothing that day.
  Future<DayEntry?> entryOn(CycleDate date) async {
    final iso = date.toIso8601();
    final row = await (select(
      dayEntries,
    )..where((row) => row.date.equals(iso))).getSingleOrNull();
    final symptoms = await _symptomsOn(iso);

    // A day with symptoms but no entry row is still a logged day.
    if (row == null) {
      if (symptoms.isEmpty) return null;
      return DayEntry(date: date, symptoms: symptoms);
    }
    return DayEntry(
      date: row.date,
      flow: row.flow,
      note: row.note,
      temperatureCentiCelsius: row.temperatureCenti,
      symptoms: symptoms,
    );
  }

  /// Every logged day between [from] and [to] inclusive, oldest first.
  Future<List<DayEntry>> entriesBetween(CycleDate from, CycleDate to) async {
    // Zero-padded ISO text sorts and compares chronologically, so this is a
    // plain string range rather than anything that needs decoding.
    final rows =
        await (select(dayEntries)
              ..where(
                (row) =>
                    row.date.isBetweenValues(from.toIso8601(), to.toIso8601()),
              )
              ..orderBy([(row) => OrderingTerm(expression: row.date)]))
            .get();

    return [
      for (final row in rows)
        DayEntry(
          date: row.date,
          flow: row.flow,
          note: row.note,
          temperatureCentiCelsius: row.temperatureCenti,
          symptoms: await _symptomsOn(row.date.toIso8601()),
        ),
    ];
  }

  /// Every day she logged anything on, the flow of those that have one, and
  /// the days she recorded having sex or taking a pregnancy test.
  ///
  /// Two plain queries over the whole history, rather than [entriesBetween]'s
  /// query per day: the calendar scrolls through all of it, and needs only
  /// which days carry something and which carry bleeding, not what.
  Future<
    ({
      Set<CycleDate> logged,
      Map<CycleDate, FlowIntensity> flow,
      Set<CycleDate> sex,
      Set<CycleDate> pregnancyTest,
    })
  >
  loggedDays() async {
    final entries = await (selectOnly(
      dayEntries,
    )..addColumns([dayEntries.date, dayEntries.flow])).get();
    final symptomDays = await (selectOnly(
      daySymptoms,
      distinct: true,
    )..addColumns([daySymptoms.date])).get();

    final marked =
        await (selectOnly(daySymptoms)
              ..addColumns([daySymptoms.date, daySymptoms.symptomKey])
              ..where(
                daySymptoms.symptomKey.isIn([
                  ...hadSexKeys,
                  ...offeredPregnancyTestKeys,
                ]),
              ))
            .get();
    final sex = <CycleDate>{};
    final pregnancyTest = <CycleDate>{};
    for (final row in marked) {
      final date = daySymptoms.date.converter.fromSql(
        row.read(daySymptoms.date)!,
      );
      final key = row.read(daySymptoms.symptomKey)!;
      (hadSexKeys.contains(key) ? sex : pregnancyTest).add(date);
    }

    final flow = <CycleDate, FlowIntensity>{};
    final logged = <CycleDate>{};
    for (final row in entries) {
      final date = dayEntries.date.converter.fromSql(
        row.read(dayEntries.date)!,
      );
      logged.add(date);
      final raw = row.read(dayEntries.flow);
      if (raw != null) {
        flow[date] = dayEntries.flow.converter.fromSql(raw)!;
      }
    }
    for (final row in symptomDays) {
      logged.add(
        daySymptoms.date.converter.fromSql(row.read(daySymptoms.date)!),
      );
    }
    return (logged: logged, flow: flow, sex: sex, pregnancyTest: pregnancyTest);
  }

  /// Writes [entry], replacing whatever was logged on that day.
  ///
  /// The entry and its symptoms are written in one transaction, so a day is
  /// never left with its note saved and its symptoms lost.
  Future<void> saveEntry(DayEntry entry) async {
    final iso = entry.date.toIso8601();
    await transaction(() async {
      await into(dayEntries).insert(
        DayEntriesCompanion.insert(
          date: entry.date,
          flow: Value(entry.flow),
          note: Value(entry.note),
          temperatureCenti: Value(entry.temperatureCentiCelsius),
        ),
        mode: InsertMode.replace,
      );
      await (delete(daySymptoms)..where((row) => row.date.equals(iso))).go();
      for (final symptom in entry.symptoms) {
        await into(daySymptoms).insert(
          DaySymptomsCompanion.insert(
            date: entry.date,
            symptomKey: symptom.key,
          ),
          mode: InsertMode.replace,
        );
      }
    });
  }

  /// Deletes everything logged on [date].
  Future<void> deleteEntry(CycleDate date) async {
    final iso = date.toIso8601();
    await transaction(() async {
      await (delete(dayEntries)..where((row) => row.date.equals(iso))).go();
      await (delete(daySymptoms)..where((row) => row.date.equals(iso))).go();
    });
  }

  /// Deletes every row in every table.
  ///
  /// Section 9 requires "delete all data" to actually delete. This is that, and
  /// it is deliberately exhaustive rather than a list someone has to remember to
  /// extend: a new table added without a line here would silently survive.
  Future<void> deleteEverything() async {
    await transaction(() async {
      for (final table in attachedDatabase.allTables) {
        await delete(table).go();
      }
    });
  }

  Future<Set<Symptom>> _symptomsOn(String isoDate) async {
    final rows = await (select(
      daySymptoms,
    )..where((row) => row.date.equals(isoDate))).get();
    return {for (final row in rows) Symptom(key: row.symptomKey)};
  }
}
