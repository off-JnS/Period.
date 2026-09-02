import 'package:period/data/database/converters.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  group('CycleDateConverter', () {
    const converter = CycleDateConverter();

    test('round-trips', () {
      for (final date in [
        aDate(2024, 5, 17),
        aDate(2024, 2, 29),
        aDate(1970, 1, 1),
        aDate(2024, 1, 5),
      ]) {
        expect(converter.fromSql(converter.toSql(date)), date);
      }
    });

    test('stores a zero-padded date', () {
      // The padding is what makes text sort chronologically. Without it,
      // '2024-1-5' would sort after '2024-10-1' and every range query would be
      // subtly wrong.
      expect(converter.toSql(aDate(2024, 1, 5)), '2024-01-05');
    });

    test('stored dates sort chronologically as plain strings', () {
      final stored = [
        aDate(2024, 10, 1),
        aDate(2024, 1, 5),
        aDate(2023, 12, 31),
      ].map(converter.toSql).toList()..sort();

      expect(stored, ['2023-12-31', '2024-01-05', '2024-10-01']);
    });

    test('rejects a value that is not a date rather than guessing', () {
      // Corrupt or hand-edited data must fail loudly. Silently returning some
      // nearby day would move a user's entry.
      expect(() => converter.fromSql('not a date'), throwsFormatException);
      expect(() => converter.fromSql('2023-02-29'), throwsFormatException);
    });
  });

  group('FlowIntensityConverter', () {
    const converter = FlowIntensityConverter();

    test('round-trips every value', () {
      for (final flow in FlowIntensity.values) {
        expect(converter.fromSql(converter.toSql(flow)), flow);
      }
    });

    test('stores the name, not the index', () {
      // By name so that reordering or inserting a value cannot silently
      // reinterpret existing rows as something the user never recorded.
      expect(converter.toSql(FlowIntensity.medium), 'medium');
      expect(converter.toSql(FlowIntensity.none), 'none');
    });

    test('rejects an unknown name rather than guessing', () {
      expect(() => converter.fromSql('torrential'), throwsStateError);
    });
  });
}
