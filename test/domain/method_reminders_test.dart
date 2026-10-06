import 'package:period/domain/logic/period_prediction.dart';
import 'package:period/domain/logic/reminders.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/domain/models/reminder_settings.dart';
import 'package:test/test.dart';

import '../support/dates.dart';

/// docs/cycle-logic.md §8, contraception reminders.
void main() {
  final today = aDate(2024, 5, 17);

  List<PlannedReminder> plan(
    ReminderSettings settings,
    ContraceptionMethod? method, {
    PeriodPrediction prediction = const PredictionsDisabled(
      CycleMode.pregnancy,
    ),
  }) => planReminders(
    settings: settings,
    prediction: prediction,
    today: today,
    method: method,
  );

  List<CycleDate> days(Iterable<PlannedReminder> planned) => [
    for (final reminder in planned) reminder.day,
  ];

  group('belongs to the method in her profile', () {
    test('a pill reminder is silent once she uses something else', () {
      const settings = ReminderSettings(pill: true);
      expect(plan(settings, ContraceptionMethod.combinedPill), isNotEmpty);
      expect(plan(settings, ContraceptionMethod.progestinPill), isNotEmpty);
      expect(plan(settings, ContraceptionMethod.ring), isEmpty);
      expect(plan(settings, ContraceptionMethod.condom), isEmpty);
      expect(plan(settings, null), isEmpty);
    });

    test('methods with nothing to remind of have no reminder', () {
      expect(MethodReminder.of(ContraceptionMethod.none), isNull);
      expect(MethodReminder.of(ContraceptionMethod.condom), isNull);
      expect(MethodReminder.of(ContraceptionMethod.other), isNull);
    });

    test('copper and hormonal IUDs and the implant share one', () {
      for (final method in [
        ContraceptionMethod.hormonalIud,
        ContraceptionMethod.copperIud,
        ContraceptionMethod.implant,
      ]) {
        expect(MethodReminder.of(method), MethodReminder.device);
      }
    });

    test('switched off, nothing is planned', () {
      expect(plan(const ReminderSettings(), ContraceptionMethod.ring), isEmpty);
    });
  });

  group('the pill', () {
    test('every day for 30 days at her pill time, by default', () {
      final planned = plan(
        const ReminderSettings(pill: true, pillHour: 22, pillMinute: 15),
        ContraceptionMethod.combinedPill,
      );
      expect(planned, hasLength(30));
      expect(planned.first.day, today);
      expect(planned.last.day, today.addDays(29));
      expect(planned.every((r) => r.kind == ReminderKind.pill), isTrue);
      expect((planned.first.hour, planned.first.minute), (22, 15));
    });

    test('a 21-day pack skips its seven break days', () {
      // The pack began 18 days ago: today is day 19, days 22-28 are breaks.
      final planned = plan(
        ReminderSettings(
          pill: true,
          pillPack: PillPack.days21,
          pillPackStart: today.subtractDays(18),
        ),
        ContraceptionMethod.combinedPill,
      );
      final first = days(planned).take(4).toList();
      expect(first, [
        today,
        today.addDays(1),
        today.addDays(2),
        // Seven break days, then the next pack.
        today.addDays(10),
      ]);
      expect(planned, hasLength(30 - 7));
    });

    test('a 24-day pack skips four', () {
      final planned = plan(
        ReminderSettings(
          pill: true,
          pillPack: PillPack.days24,
          pillPackStart: today,
        ),
        ContraceptionMethod.combinedPill,
      );
      expect(days(planned), isNot(contains(today.addDays(24))));
      expect(days(planned), contains(today.addDays(28)));
      expect(planned, hasLength(30 - 4));
    });

    test('a pack starting in a few days is counted back from', () {
      // Starting in 3 days means the break is running now.
      final planned = plan(
        ReminderSettings(
          pill: true,
          pillPack: PillPack.days21,
          pillPackStart: today.addDays(3),
        ),
        ContraceptionMethod.combinedPill,
      );
      expect(days(planned).first, today.addDays(3));
    });

    test('with a break but no first day, every day, never fewer', () {
      final planned = plan(
        const ReminderSettings(pill: true, pillPack: PillPack.days21),
        ContraceptionMethod.combinedPill,
      );
      expect(planned, hasLength(30));
    });
  });

  group('the ring', () {
    test('out after three weeks, in after the break, every 28 days', () {
      final inserted = aDate(2024, 5, 10);
      final planned = plan(
        ReminderSettings(ring: true, ringInserted: inserted),
        ContraceptionMethod.ring,
      );
      expect(planned.take(4).map((r) => (r.day, r.kind)), [
        (aDate(2024, 5, 31), ReminderKind.ringOut),
        (aDate(2024, 6, 7), ReminderKind.ringIn),
        (aDate(2024, 6, 28), ReminderKind.ringOut),
        (aDate(2024, 7, 5), ReminderKind.ringIn),
      ]);
      expect(
        days(planned).every(
          (day) => !day.isAfter(today.addDays(methodReminderHorizonDays)),
        ),
        isTrue,
      );
    });

    test('a ring put in months ago still lands on its own rhythm', () {
      final inserted = aDate(2023, 1, 1);
      final planned = plan(
        ReminderSettings(ring: true, ringInserted: inserted),
        ContraceptionMethod.ring,
      );
      for (final reminder in planned) {
        expect(reminder.day.isBefore(today), isFalse);
        final offset = inserted.daysUntil(reminder.day) % 28;
        expect(offset, reminder.kind == ReminderKind.ringOut ? 21 : 0);
      }
    });

    test('with no day entered, nothing', () {
      expect(
        plan(const ReminderSettings(ring: true), ContraceptionMethod.ring),
        isEmpty,
      );
    });
  });

  test('the patch: changed on days 8 and 15, off on 22, new on 29', () {
    final planned = plan(
      ReminderSettings(patch: true, patchStarted: today),
      ContraceptionMethod.patch,
    );
    expect(planned.take(4).map((r) => (r.day, r.kind)), [
      (today.addDays(7), ReminderKind.patchChange),
      (today.addDays(14), ReminderKind.patchChange),
      (today.addDays(21), ReminderKind.patchOff),
      (today.addDays(28), ReminderKind.patchOn),
    ]);
  });

  group('the injection', () {
    test('a week before it is due, and on the day', () {
      final planned = plan(
        ReminderSettings(
          injection: true,
          injectionLast: today,
          injectionWeeks: 12,
        ),
        ContraceptionMethod.injection,
      );
      expect(planned.map((r) => (r.day, r.kind)), [
        (today.addDays(77), ReminderKind.injectionSoon),
        (today.addDays(84), ReminderKind.injectionDue),
      ]);
    });

    test('an interval outside the offered range is clamped', () {
      final planned = plan(
        ReminderSettings(
          injection: true,
          injectionLast: today,
          injectionWeeks: 40,
        ),
        ContraceptionMethod.injection,
      );
      expect(planned.last.day, today.addDays(14 * 7));
    });

    test('an injection already overdue is not reminded of late', () {
      expect(
        plan(
          ReminderSettings(
            injection: true,
            injectionLast: today.subtractDays(200),
          ),
          ContraceptionMethod.injection,
        ),
        isEmpty,
      );
    });
  });

  test('an IUD or implant: the chosen weeks before, and on the day', () {
    final due = aDate(2029, 3, 1);
    final planned = plan(
      ReminderSettings(
        device: true,
        deviceReplaceBy: due,
        deviceWeeksBefore: 8,
        methodHour: 10,
      ),
      ContraceptionMethod.hormonalIud,
    );
    expect(planned.map((r) => (r.day, r.kind, r.hour)), [
      (due.subtractDays(56), ReminderKind.deviceSoon, 10),
      (due, ReminderKind.deviceDue, 10),
    ]);
  });

  group('together', () {
    test('never more than iOS allows, contraception first', () {
      final planned = plan(
        ReminderSettings(
          dailyLog: true,
          periodComing: true,
          pill: true,
          pillPack: PillPack.everyDay,
          pillPackStart: today,
        ),
        ContraceptionMethod.combinedPill,
        prediction: PredictedPeriod(
          earliest: today.addDays(10),
          latest: today.addDays(14),
        ),
      );
      expect(planned.length, maxPlannedReminders);
      final kinds = planned.map((r) => r.kind).toList();
      expect(kinds.where((k) => k == ReminderKind.pill), hasLength(30));
      expect(kinds, contains(ReminderKind.periodComing));
      expect(kinds.where((k) => k == ReminderKind.dailyLog), hasLength(29));
    });

    test('earliest first, by day and then by time', () {
      final planned = plan(
        const ReminderSettings(dailyLog: true, pill: true, hour: 22),
        ContraceptionMethod.progestinPill,
      );
      for (var i = 1; i < planned.length; i++) {
        final a = planned[i - 1];
        final b = planned[i];
        expect(
          a.day.isBefore(b.day) ||
              (a.day == b.day &&
                  a.hour * 60 + a.minute <= b.hour * 60 + b.minute),
          isTrue,
        );
      }
    });
  });
}
