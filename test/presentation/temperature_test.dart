import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/analysis/temperature_chart.dart';
import 'package:period/presentation/log/temperature.dart';

import '../support/dates.dart';

void main() {
  group('parseTemperature', () {
    int? centi(String input) => switch (parseTemperature(input)) {
      ValidTemperature(:final centi) => centi,
      _ => null,
    };

    test('reads a comma or a point as the decimal mark', () {
      expect(centi('36,45'), 3645);
      expect(centi('36.45'), 3645);
    });

    test('reads one decimal or none', () {
      expect(centi('36,5'), 3650);
      expect(centi('37'), 3700);
    });

    test('ignores surrounding spaces', () => expect(centi(' 36,7 '), 3670));

    test('nothing typed is no reading, not an error', () {
      expect(parseTemperature(''), isA<NoTemperature>());
      expect(parseTemperature('   '), isA<NoTemperature>());
    });

    test('refuses anything outside 34-43 °C', () {
      for (final typo in ['33,99', '43,01', '3.65', '365', '99']) {
        expect(parseTemperature(typo), isA<InvalidTemperature>(), reason: typo);
      }
      expect(centi('34'), 3400);
      expect(centi('43'), 4300);
    });

    test('refuses what is not a temperature', () {
      for (final junk in ['abc', '36,456', '36,', ',5', '36 5', '-36']) {
        expect(parseTemperature(junk), isA<InvalidTemperature>(), reason: junk);
      }
    });
  });

  group('formatTemperature', () {
    test('uses the language decimal mark and two decimals', () {
      expect(formatTemperature(3645, 'de'), '36,45 °C');
      expect(formatTemperature(3650, 'en'), '36.50 °C');
    });
  });

  group('temperatureChartFrom', () {
    final today = aDate(2024, 5, 17);
    final starts = [aDate(2024, 4, 3), aDate(2024, 5, 1)];

    test('nothing ever logged means no chart at all', () {
      expect(
        temperatureChartFrom(
          periodStarts: starts,
          temperatures: const {},
          positiveTests: const {},
          today: today,
        ),
        isNull,
      );
    });

    test('shows the current cycle, by cycle day', () {
      final chart = temperatureChartFrom(
        periodStarts: starts,
        temperatures: {aDate(2024, 5, 1): 3640, aDate(2024, 5, 3): 3650},
        positiveTests: const {},
        today: today,
      )!;
      expect(chart.cycleStart, aDate(2024, 5, 1));
      expect(chart.readings, {1: 3640, 3: 3650});
    });

    test('falls back to the latest cycle with readings', () {
      final chart = temperatureChartFrom(
        periodStarts: starts,
        temperatures: {aDate(2024, 4, 10): 3660},
        positiveTests: {aDate(2024, 4, 16)},
        today: today,
      )!;
      expect(chart.cycleStart, aDate(2024, 4, 3));
      expect(chart.readings, {8: 3660});
      expect(chart.positiveTestDays, {14});
      // The finished cycle's own length: 3 Apr to 30 Apr.
      expect(chart.days, 28);
    });

    test('a young cycle still spans 28 days, not a stretched few', () {
      final chart = temperatureChartFrom(
        periodStarts: [aDate(2024, 5, 14)],
        temperatures: {aDate(2024, 5, 14): 3640},
        positiveTests: const {},
        today: today,
      )!;
      expect(chart.days, 28);
    });

    test('a long cycle keeps its length', () {
      final chart = temperatureChartFrom(
        periodStarts: [aDate(2024, 3, 1), aDate(2024, 4, 10)],
        temperatures: {aDate(2024, 3, 5): 3640},
        positiveTests: const {},
        today: today,
      )!;
      expect(chart.days, 40);
    });
  });
}
