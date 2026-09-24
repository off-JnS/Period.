import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/logic/reminders.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

void main() {
  final today = aDate(2024, 5, 17);
  final window = PredictedPeriod(
    earliest: aDate(2024, 5, 26),
    latest: aDate(2024, 5, 30),
  );

  List<PlannedReminder> plan(
    ReminderSettings settings, {
    PeriodPrediction? prediction,
  }) => planReminders(
    settings: settings,
    prediction: prediction ?? window,
    today: today,
  );

  test('nothing is planned while every reminder is off', () {
    expect(plan(const ReminderSettings()), isEmpty);
  });

  group('the period reminder', () {
    const on = ReminderSettings(periodComing: true);

    test('falls the chosen number of days before the window opens', () {
      expect(plan(on), [
        PlannedReminder(
          day: aDate(2024, 5, 24),
          hour: 9,
          minute: 0,
          kind: ReminderKind.periodComing,
        ),
      ]);
      expect(plan(on.copyWith(daysBefore: 5)).single.day, aDate(2024, 5, 21));
    });

    test('counts from the first day of the window, not its middle', () {
      // Arriving after the earliest plausible start would defeat it.
      expect(
        plan(on.copyWith(daysBefore: 1)).single.day,
        window.earliest.subtractDays(1),
      );
    });

    test('uses her chosen time', () {
      final reminder = plan(on.copyWith(hour: 20, minute: 30)).single;
      expect((reminder.hour, reminder.minute), (20, 30));
    });

    test('clamps a lead time outside the offered range', () {
      expect(plan(on.copyWith(daysBefore: 0)).single.day, aDate(2024, 5, 25));
      expect(plan(on.copyWith(daysBefore: 40)).single.day, aDate(2024, 5, 21));
    });

    test('is dropped when its day has already passed', () {
      final soon = PredictedPeriod(
        earliest: aDate(2024, 5, 18),
        latest: aDate(2024, 5, 22),
      );
      expect(plan(on, prediction: soon), isEmpty);
    });

    test('can fall on today; the scheduler decides if the time has gone', () {
      final soon = PredictedPeriod(
        earliest: aDate(2024, 5, 19),
        latest: aDate(2024, 5, 23),
      );
      expect(plan(on, prediction: soon).single.day, today);
    });

    test('is never planned without an estimate', () {
      // docs/cycle-logic.md §8: it never makes a prediction of its own.
      for (final prediction in <PeriodPrediction>[
        const NotEnoughCycles(have: 1, need: 2),
        const CyclesTooVariable(9),
        for (final mode in CycleMode.values.where(
          (m) => m != CycleMode.natural,
        ))
          PredictionsDisabled(mode),
      ]) {
        expect(
          plan(on, prediction: prediction),
          isEmpty,
          reason: '$prediction',
        );
      }
    });

    test('is kept even when the window is further off than a month', () {
      final far = PredictedPeriod(
        earliest: today.addDays(50),
        latest: today.addDays(56),
      );
      expect(plan(on, prediction: far).single.day, today.addDays(48));
    });
  });

  group('the daily reminder', () {
    const on = ReminderSettings(dailyLog: true, hour: 21, minute: 15);

    test('covers the horizon, one a day from today', () {
      final planned = plan(on);
      expect(planned, hasLength(dailyReminderHorizonDays));
      expect(planned.first.day, today);
      expect(planned.last.day, today.addDays(dailyReminderHorizonDays - 1));
      expect(planned.map((r) => r.day).toSet(), hasLength(planned.length));
      expect(planned.every((r) => r.hour == 21 && r.minute == 15), isTrue);
    });

    test('does not depend on an estimate', () {
      expect(
        plan(on, prediction: const PredictionsDisabled(CycleMode.pregnancy)),
        hasLength(dailyReminderHorizonDays),
      );
    });

    test('runs across a month end without skipping or repeating a day', () {
      final planned = planReminders(
        settings: on,
        prediction: window,
        today: aDate(2024, 2, 20),
      );
      final days = planned.map((r) => r.day).toList();
      for (var i = 1; i < days.length; i++) {
        expect(days[i - 1].daysUntil(days[i]), 1);
      }
      expect(days, contains(aDate(2024, 2, 29)));
    });
  });

  test('both together stay under the iOS limit of 64 pending', () {
    final planned = plan(
      const ReminderSettings(periodComing: true, dailyLog: true),
    );
    expect(planned, hasLength(dailyReminderHorizonDays + 1));
    expect(planned.length, lessThanOrEqualTo(64));
  });

  test('anyEnabled reflects either switch', () {
    expect(const ReminderSettings().anyEnabled, isFalse);
    expect(const ReminderSettings(periodComing: true).anyEnabled, isTrue);
    expect(const ReminderSettings(dailyLog: true).anyEnabled, isTrue);
  });
}
