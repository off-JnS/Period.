import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  final window = PredictedPeriod(
    earliest: aDate(2024, 5, 26),
    latest: aDate(2024, 5, 30),
  );

  test('before the window, the window counted in days', () {
    expect(
      countdownTo(window, aDate(2024, 5, 14)),
      const CountdownUpcoming(fromDays: 12, toDays: 16),
    );
  });

  test('the day before it opens is "in 1–5 days"', () {
    expect(
      countdownTo(window, aDate(2024, 5, 25)),
      const CountdownUpcoming(fromDays: 1, toDays: 5),
    );
  });

  test('never a single number, even for the narrowest window', () {
    final narrow = PredictedPeriod(
      earliest: aDate(2024, 5, 26),
      latest: aDate(2024, 5, 28),
    );
    final countdown =
        countdownTo(narrow, aDate(2024, 5, 20))! as CountdownUpcoming;
    expect(countdown.toDays, greaterThan(countdown.fromDays));
  });

  test('inside the window, from its first day to its last', () {
    for (var d = 26; d <= 30; d++) {
      expect(
        countdownTo(window, aDate(2024, 5, d)),
        const CountdownInWindow(),
        reason: 'May $d',
      );
    }
  });

  test('after the window, later than estimated', () {
    expect(countdownTo(window, aDate(2024, 5, 31)), const CountdownPastWindow());
    expect(countdownTo(window, aDate(2024, 7, 1)), const CountdownPastWindow());
  });

  test('across a month and a year boundary', () {
    final newYear = PredictedPeriod(
      earliest: aDate(2025, 1, 2),
      latest: aDate(2025, 1, 5),
    );
    expect(
      countdownTo(newYear, aDate(2024, 12, 30)),
      const CountdownUpcoming(fromDays: 3, toDays: 6),
    );
  });

  test('no countdown without a window', () {
    expect(countdownTo(const NotEnoughCycles(have: 1, need: 2), anyDate()), isNull);
    expect(countdownTo(const CyclesTooVariable(9), anyDate()), isNull);
    expect(
      countdownTo(const PredictionsDisabled(CycleMode.pregnancy), anyDate()),
      isNull,
    );
  });
}
