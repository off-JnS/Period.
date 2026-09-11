import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/logic/reminder_schedule.dart';
import '../domain/models/cycle_date.dart';
import '../domain/models/reminder_schedule.dart';
import '../domain/models/reminder_time.dart';

/// Schedules the log reminder the user asked for.
///
/// An interface for the same reason [AppLock] and [DatabaseKeyStore] are ones:
/// this is the only part of the app that reaches the notification plugin, so
/// everything around it -- when a reminder is scheduled, when it is dropped,
/// what happens when she refuses the permission -- is testable without a
/// device. Section 6 keeps `flutter_secure_storage` behind a seam for the same
/// reason; nothing outside this file imports the plugin or `timezone`.
///
/// Nothing here reads a cycle, a prediction or a mode. Section 7 of
/// docs/cycle-logic.md makes that the defining property of a reminder, and
/// architecture_test.dart pins it against this file by name.
abstract class Reminders {
  /// Asks the operating system for permission to show notifications.
  ///
  /// Returns whether it was granted. Called when she turns reminders on, never
  /// at launch: a permission prompt on first open, before she has asked for
  /// anything, is the prompt everyone refuses.
  Future<bool> requestPermission();

  /// Whether the operating system will currently show a notification.
  ///
  /// Asked without prompting. A permission granted once does not stay granted:
  /// she can revoke it in system settings, and Android revokes it on its own
  /// for apps left unused for a few months. Either way nothing tells the app --
  /// the reminder simply stops arriving, and the switch in settings goes on
  /// saying it is on.
  ///
  /// Only meaningful alongside her own setting. On a fresh install this is
  /// false because she has never been asked, which is not the same as blocked;
  /// see [SettingsScreen], which only says anything when her reminder is on and
  /// this is false.
  Future<bool> hasPermission();

  /// Makes what is scheduled match [schedule], replacing whatever was there.
  ///
  /// [today] and [now] locate the first firing of each day; everything after
  /// that repeats. Both are passed rather than read from a clock, per CLAUDE.md
  /// section 3.
  ///
  /// [title] and [body] are passed in already localised because section 8 keeps
  /// every user-facing string in the ARB files, and the data layer has no
  /// [BuildContext] to resolve one from.
  Future<void> applySchedule(
    ReminderSchedule schedule, {
    required CycleDate today,
    required ReminderTime now,
    required String title,
    required String body,
  });

  /// Drops the reminder for [weekday] and puts it back starting a week later.
  ///
  /// This is the skip-if-already-logged rule. Cancelling alone would end the
  /// series permanently: she would log one day and never be reminded again,
  /// which is the failure docs/cycle-logic.md section 7 splits [nextReminder]
  /// and [shouldRemindOn] apart to avoid.
  Future<void> skipToday(
    ReminderSchedule schedule, {
    required CycleDate today,
    required String title,
    required String body,
  });

  /// Removes every scheduled reminder.
  Future<void> cancelAll();
}

/// The identifier of the single series a daily reminder uses.
///
/// Zero, which no weekday can be, so it can never collide with one. A daily
/// reminder is deliberately not seven weekly ones: it repeats on the time
/// alone, so it has no weekday to be keyed by.
const dailyReminderId = 0;

/// The identifier of the series for [weekday], 1 (Monday) through 7 (Sunday).
///
/// The weekday itself, so one day can be cancelled and rescheduled without
/// disturbing the other six. Stable across runs and across versions: an id that
/// changed would leave the old notification scheduled forever with nothing able
/// to cancel it.
int reminderIdFor(int weekday) => weekday;

/// The real one, over `flutter_local_notifications`.
class LocalNotificationReminders implements Reminders {
  /// Creates the reminders.
  LocalNotificationReminders({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Android's notification channel. Named in the ARB-supplied [_channelName]
  /// at initialise time; the id is never shown and never changes, because
  /// changing it orphans the channel the user has already configured.
  static const _channelId = 'log_reminder';

  /// Wires up the plugin. Call once, before anything else here.
  ///
  /// [channelName] and [channelDescription] are what Android shows in its own
  /// notification settings, so they are localised strings like everything else.
  Future<void> initialize({
    required String channelName,
    required String channelDescription,
  }) async {
    _channelName = channelName;
    _channelDescription = channelDescription;

    await _plugin.initialize(
      const InitializationSettings(
        // The launcher icon. A notification with no icon does not appear at all
        // on Android, and there is nothing to see in a log when it does not.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // All three false. She is asked when she turns reminders on, not the
        // first time the app opens -- see [requestPermission].
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  String _channelName = '';
  String _channelDescription = '';

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }

    // A platform with neither. Nothing will be shown, and saying so is better
    // than reporting a success that produces no notification.
    return false;
  }

  @override
  Future<bool> hasPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }

    return false;
  }

  @override
  Future<void> applySchedule(
    ReminderSchedule schedule, {
    required CycleDate today,
    required ReminderTime now,
    required String title,
    required String body,
  }) async {
    // Cleared first, unconditionally. She may have deselected a day, and a
    // notification for a day no longer chosen would otherwise keep firing with
    // nothing left pointing at it.
    await cancelAll();
    if (!schedule.enabled) return;

    final weekdays = schedule.validWeekdays;

    // All seven days is one series repeating on the time alone, not seven
    // weekly ones. Seven would behave the same, but both platforms cap how many
    // notifications an app may have pending, and spending seven slots on what
    // one expresses is careless with a budget this app does not control.
    if (weekdays.length == 7) {
      final due = nextReminder(schedule: schedule, today: today, now: now);
      if (due is! ReminderDue) return;
      await _scheduleOne(
        id: dailyReminderId,
        due: due,
        title: title,
        body: body,
        repeat: DateTimeComponents.time,
      );
      return;
    }

    for (final weekday in weekdays) {
      final due = nextReminder(
        // A single-weekday copy, so the first firing of *this* day comes from
        // the same tested function that answers the general question. The
        // alternative -- a second date search here -- is a second thing to keep
        // correct, in the layer with no tests that run without a device.
        schedule: schedule.copyWith(weekdays: {weekday}),
        today: today,
        now: now,
      );
      if (due is! ReminderDue) continue;

      await _scheduleOne(
        id: reminderIdFor(weekday),
        due: due,
        title: title,
        body: body,
        repeat: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> skipToday(
    ReminderSchedule schedule, {
    required CycleDate today,
    required String title,
    required String body,
  }) async {
    if (!schedule.enabled) return;
    if (!schedule.fallsOnWeekday(today.weekday)) return;

    final daily = schedule.validWeekdays.length == 7;
    // A daily reminder is one series under [dailyReminderId], not seven keyed
    // by weekday. Cancelling by today's weekday would cancel nothing at all,
    // and the reminder she has just made unnecessary would still arrive.
    final id = daily ? dailyReminderId : reminderIdFor(today.weekday);

    await _plugin.cancel(id);

    // Straight back on, starting at the next occurrence. For a weekly reminder
    // that is a week from today; for a daily one it is tomorrow. Either way the
    // series continues, which is the whole point of not simply cancelling.
    final due = ReminderDue(
      date: today.addDays(daily ? 1 : 7),
      time: schedule.time,
    );
    await _scheduleOne(
      id: id,
      due: due,
      title: title,
      body: body,
      repeat: daily
          ? DateTimeComponents.time
          : DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> _scheduleOne({
    required int id,
    required ReminderDue due,
    required String title,
    required String body,
    required DateTimeComponents repeat,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _instantFor(due),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          // Deliberately not high. A reminder to log is not urgent, and
          // importance high means a heads-up banner over whatever is on screen
          // -- which section 9 keeps this app's notifications well clear of.
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Not exact. See the comment beside RECEIVE_BOOT_COMPLETED in
      // AndroidManifest.xml: this still fires in Doze, and it needs no
      // exact-alarm permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
      matchDateTimeComponents: repeat,
    );
  }

  /// The instant a [ReminderDue] falls on.
  ///
  /// docs/cycle-logic.md section 7 keeps the domain's answer as a calendar day
  /// and a wall-clock time, and resolving it to a point in time is this layer's
  /// job. Here is the honest limit of how well that is done:
  ///
  /// `timezone` needs an IANA zone name to know when the clocks change, and
  /// getting one requires a package section 6 does not allow. So the location
  /// below is built from the offset in force *now*, which is right until the
  /// clocks change.
  ///
  /// What saves it is [DateTimeComponents]: the repeat is handled by the
  /// platform in wall-clock terms -- on iOS by a calendar trigger on the hour
  /// and minute, which is correct across a DST change by construction -- so the
  /// offset only ever affects the first firing. The worst case is one reminder
  /// an hour early or late, once, after which the next reschedule corrects it.
  ///
  /// It cannot move a date in the database. A notification writes nothing; the
  /// shift section 3 is about is not reachable from here.
  tz.TZDateTime _instantFor(ReminderDue due) {
    final location = _currentOffsetLocation();
    return tz.TZDateTime(
      location,
      due.date.year,
      due.date.month,
      due.date.day,
      due.time.hour,
      due.time.minute,
    );
  }

  /// A fixed-offset location matching the device right now.
  ///
  /// Built rather than looked up, because looking one up means knowing the zone
  /// name. `DateTime.now()` appears here and nowhere else in this file: section
  /// 3 confines it to the [Clock] abstraction *for cycle days*, and this is not
  /// one -- it is the device's UTC offset, which no [CycleDate] can carry and
  /// which is never stored.
  tz.Location _currentOffsetLocation() {
    final offset = DateTime.now().timeZoneOffset.inMilliseconds;
    return tz.Location(
      'local',
      // One zone, from the beginning of time, never changing.
      const [tz.TZDateTime.minMillisecondsSinceEpoch],
      [offset],
      [tz.TimeZone(offset, isDst: false, abbreviation: 'local')],
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
