import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:period/data/reminders/reminder_scheduler.dart';
import 'package:period/domain/logic/reminders.dart';
import 'package:timezone/timezone.dart' as tz;

import '../support/dates.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

void main() {
  late _MockPlugin plugin;

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime.utc(2000));
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
  });

  setUp(() {
    plugin = _MockPlugin();
    when(() => plugin.initialize(settings: any(named: 'settings')))
        .thenAnswer((_) async => true);
    when(() => plugin.cancelAll()).thenAnswer((_) async {});
    when(
      () => plugin.zonedSchedule(
        id: any(named: 'id'),
        scheduledDate: any(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        title: any(named: 'title'),
      ),
    ).thenAnswer((_) async {});
  });

  PlannedReminder at(int day, int hour, [int minute = 0]) => PlannedReminder(
    day: aDate(2024, 5, day),
    hour: hour,
    minute: minute,
    kind: ReminderKind.dailyLog,
  );

  List<({tz.TZDateTime date, String? title})> scheduled() {
    final captured = verify(
      () => plugin.zonedSchedule(
        id: any(named: 'id'),
        scheduledDate: captureAny(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        title: captureAny(named: 'title'),
      ),
    ).captured;
    return [
      for (var i = 0; i < captured.length; i += 2)
        (date: captured[i] as tz.TZDateTime, title: captured[i + 1] as String?),
    ];
  }

  Future<void> schedule(
    List<PlannedReminder> reminders, {
    required DateTime now,
  }) => LocalNotificationsReminderScheduler(
    plugin: plugin,
    now: () => now,
  ).replaceAll(reminders, text: 'Reminder', channelName: 'Reminders');

  test('cancels everything before scheduling afresh', () async {
    await schedule([], now: DateTime(2024, 5, 17, 8));
    verify(() => plugin.cancelAll()).called(1);
    verifyNever(
      () => plugin.zonedSchedule(
        id: any(named: 'id'),
        scheduledDate: any(named: 'scheduledDate'),
        notificationDetails: any(named: 'notificationDetails'),
        androidScheduleMode: any(named: 'androidScheduleMode'),
        title: any(named: 'title'),
      ),
    );
  });

  test('schedules each at its local time on its day', () async {
    await schedule([at(18, 9), at(19, 21, 30)], now: DateTime(2024, 5, 17, 8));
    final dates = scheduled()
        .map(
          (s) => DateTime.fromMillisecondsSinceEpoch(
            s.date.millisecondsSinceEpoch,
          ),
        )
        .toList();
    expect(dates, [DateTime(2024, 5, 18, 9), DateTime(2024, 5, 19, 21, 30)]);
  });

  test("skips today's reminder once its time has passed", () async {
    await schedule([at(17, 9), at(18, 9)], now: DateTime(2024, 5, 17, 10));
    expect(
      scheduled().map(
        (s) =>
            DateTime.fromMillisecondsSinceEpoch(s.date.millisecondsSinceEpoch),
      ),
      [DateTime(2024, 5, 18, 9)],
    );
  });

  test("keeps today's reminder while its time is still ahead", () async {
    await schedule([at(17, 9)], now: DateTime(2024, 5, 17, 8, 59));
    expect(scheduled(), hasLength(1));
  });

  test('every notification says only the neutral text (section 9)', () async {
    await schedule([at(18, 9), at(19, 9)], now: DateTime(2024, 5, 17, 8));
    expect(scheduled().map((s) => s.title), everyElement('Reminder'));
  });

  test('stays on the local clock time across a daylight-saving change', () {
    // The reason for one-off instants: in Central Europe the clocks go
    // forward on 31 March 2024. A 9:00 reminder must still be 9:00 local on
    // both sides, whatever the UTC offset does.
    return schedule([
      PlannedReminder(
        day: aDate(2024, 3, 30),
        hour: 9,
        minute: 0,
        kind: ReminderKind.dailyLog,
      ),
      PlannedReminder(
        day: aDate(2024, 4, 1),
        hour: 9,
        minute: 0,
        kind: ReminderKind.dailyLog,
      ),
    ], now: DateTime(2024, 3, 29)).then((_) {
      final local = scheduled()
          .map(
            (s) => DateTime.fromMillisecondsSinceEpoch(
              s.date.millisecondsSinceEpoch,
            ),
          )
          .toList();
      expect(local.map((d) => (d.hour, d.minute)), [(9, 0), (9, 0)]);
    });
  });

  test('surfaces a platform failure as an exception to catch', () {
    // Guards the assumption ReminderSync relies on: failures surface as
    // exceptions it can catch, not as a hang.
    when(() => plugin.cancelAll()).thenThrow(PlatformException(code: 'x'));
    expect(
      schedule([at(18, 9)], now: DateTime(2024, 5, 17)),
      throwsA(isA<PlatformException>()),
    );
  });
}
