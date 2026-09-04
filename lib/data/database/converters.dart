import 'package:drift/drift.dart';

import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';

/// Stores a [CycleDate] as a zero-padded `YYYY-MM-DD` string.
///
/// Text rather than an integer day number for two reasons. Zero-padded ISO
/// dates sort lexicographically in the same order they sort chronologically, so
/// `ORDER BY` and `BETWEEN` stay correct without decoding anything. And a
/// database opened by hand, or a backup read by a worried user, shows dates a
/// person can read instead of an offset only this app can interpret.
///
/// No [DateTime] is involved at any point: section 3 keeps cycle days free of
/// timestamps, and a text column cannot smuggle one in.
class CycleDateConverter extends TypeConverter<CycleDate, String>
    with JsonTypeConverter<CycleDate, String> {
  /// Creates the converter.
  const CycleDateConverter();

  @override
  CycleDate fromSql(String fromDb) => CycleDate.parseIso8601(fromDb);

  @override
  String toSql(CycleDate value) => value.toIso8601();
}

/// Stores a [FlowIntensity] by name.
///
/// By name rather than by index so that reordering or inserting a value cannot
/// silently reinterpret existing rows as something the user never recorded.
/// An unrecognised name throws rather than guessing.
class FlowIntensityConverter extends TypeConverter<FlowIntensity, String>
    with JsonTypeConverter<FlowIntensity, String> {
  /// Creates the converter.
  const FlowIntensityConverter();

  @override
  FlowIntensity fromSql(String fromDb) =>
      FlowIntensity.values.firstWhere((value) => value.name == fromDb);

  @override
  String toSql(FlowIntensity value) => value.name;
}
