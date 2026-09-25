import 'package:drift/drift.dart';

import 'converters.dart';

/// The days the user marked a period as starting.
///
/// This is the source of truth for cycle boundaries. Section 4 computes cycle
/// length, phase, the fertile window and everything else on read from these
/// dates, every time, so none of those appear as columns here and none ever
/// should -- a user correcting a start date would leave them stale instantly.
@DataClassName('PeriodStartRow')
class PeriodStarts extends Table {
  /// The calendar day the period started.
  TextColumn get date => text().map(const CycleDateConverter())();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// One row per calendar day the user logged something on.
///
/// Every column but the date is nullable, per section 5: nobody logs everything
/// every day, and a null means the user did not record it rather than that the
/// value is zero or none.
@DataClassName('DayEntryRow')
class DayEntries extends Table {
  /// The calendar day this entry describes.
  TextColumn get date => text().map(const CycleDateConverter())();

  /// How heavy the bleeding was, if recorded.
  TextColumn get flow =>
      text().map(const FlowIntensityConverter()).nullable()();

  /// The user's own note. Free text, never parsed.
  TextColumn get note => text().nullable()();

  /// Basal body temperature in hundredths of a degree Celsius. Added in schema
  /// version 3; null for every day logged before it, and for any day without a
  /// reading.
  IntColumn get temperatureCenti => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// What the user logged on a day, as a many-to-many keyed by string.
///
/// Section 5 is explicit that symptoms are a separate table keyed by string and
/// never fixed columns, so that adding a symptom never requires a migration.
/// The key is an arbitrary string; a new symptom is simply a new row.
///
/// Deliberately not a foreign key onto a symptoms catalogue table. A catalogue
/// would have to be migrated every time the app learns a new symptom, which is
/// the exact thing section 5 rules out.
@DataClassName('DaySymptomRow')
class DaySymptoms extends Table {
  /// The calendar day the symptom was logged on.
  TextColumn get date => text().map(const CycleDateConverter())();

  /// The symptom's stable key, e.g. `cramps`. Translated for display from the
  /// ARB files, never shown raw.
  TextColumn get symptomKey => text()();

  @override
  Set<Column<Object>> get primaryKey => {date, symptomKey};
}

/// The user's settings, one row per setting. Added in schema version 2.
///
/// Key/value rather than a column per setting, for the same reason symptoms are
/// keyed by string: a new setting is a new row, never a migration. Section 5
/// calls migrations the most dangerous code in the app, so the table is shaped
/// to need as few of them as possible.
///
/// Stored here, inside the encrypted database, rather than in a preferences
/// file: a mode such as "pregnancy" is exactly the kind of fact section 1 says
/// must not sit on the device in plain text.
@DataClassName('SettingRow')
class AppSettings extends Table {
  /// The setting's stable key, e.g. `cycle_mode`.
  TextColumn get settingKey => text()();

  /// The stored value, as text. Read back defensively: a value this build does
  /// not understand falls back to the default rather than failing to start.
  TextColumn get settingValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {settingKey};
}
