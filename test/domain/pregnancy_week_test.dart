import 'package:period/domain/logic/pregnancy_week.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  final lastPeriod = aDate(2024, 3, 1);

  PregnancyCount on(int daysLater, [List<dynamic>? starts]) => pregnancyCountOn(
    lastPeriod.addDays(daysLater),
    starts?.cast() ?? [lastPeriod],
  );

  PregnancyWeek weekOf(PregnancyCount count) =>
      (count as PregnancyCounting).week;

  test('the first day of the last period is 0+0', () {
    expect(weekOf(on(0)), const PregnancyWeek(weeks: 0, days: 0));
  });

  test('counts completed weeks plus days', () {
    expect(weekOf(on(6)), const PregnancyWeek(weeks: 0, days: 6));
    expect(weekOf(on(7)), const PregnancyWeek(weeks: 1, days: 0));
    expect(weekOf(on(87)), const PregnancyWeek(weeks: 12, days: 3));
  });

  test('counts across a leap day without skipping it', () {
    // 1 Feb 2024 to 1 Mar 2024 is 29 days in a leap year.
    expect(
      weekOf(pregnancyCountOn(aDate(2024, 3, 1), [aDate(2024, 2, 1)])),
      const PregnancyWeek(weeks: 4, days: 1),
    );
  });

  test('uses the latest period start, whatever the order', () {
    final count = pregnancyCountOn(aDate(2024, 3, 15), [
      lastPeriod,
      aDate(2024, 1, 3),
      aDate(2024, 2, 1),
    ]);
    expect(weekOf(count), const PregnancyWeek(weeks: 2, days: 0));
  });

  test('ignores a start after today', () {
    final count = pregnancyCountOn(aDate(2024, 3, 8), [
      lastPeriod,
      aDate(2024, 4, 1),
    ]);
    expect(weekOf(count), const PregnancyWeek(weeks: 1, days: 0));
  });

  test('no period start means nothing to count from', () {
    expect(
      pregnancyCountOn(aDate(2024, 3, 8), []),
      isA<PregnancyNeedsLastPeriod>(),
    );
  });

  test('runs to 44+0 and stops after it', () {
    expect(weekOf(on(pregnancyCounterLastDay)).weeks, 44);
    expect(weekOf(on(pregnancyCounterLastDay)).days, 0);
    expect(on(pregnancyCounterLastDay + 1), isA<PregnancyCounterEnded>());
  });

  test('totalDays matches the days elapsed', () {
    expect(weekOf(on(100)).totalDays, 100);
  });
}
