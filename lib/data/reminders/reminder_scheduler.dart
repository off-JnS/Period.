import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/logic/reminders.dart';
import '../system_clock.dart';

/// Puts reminders in front of the operating system.
///
/// An interface so nothing else depends on `flutter_local_notifications`, as
/// with `DeviceAuthenticator`, and so reminders can be tested without a
/// platform channel.
abstract interface class ReminderScheduler {
  /// Asks for permission to show notifications. True when granted.
  Future<bool> requestPermission();

  /// Cancels every scheduled reminder and schedules [reminders] instead.
  ///
  /// Every notification carries only [text] (CLAUDE.md §9). [channelName] is
  /// how Android lists the reminders in the phone's notification settings.
  Future<void> replaceAll(
    List<PlannedReminder> reminders, {
    required String text,
    required String channelName,
  });
}

/// The real thing, over `flutter_local_notifications`.
///
/// Schedules one-off notifications at absolute instants rather than using the
/// plugin's daily repeat. A repeat has to be pinned to a named time zone, and
/// finding the device's zone name needs a package that is not on the
/// allowlist; pinned to UTC instead, a "9:00" reminder would drift to 8:00 or
/// 10:00 at every daylight-saving change. An instant computed from the
/// device's own local calendar for each day does not drift, and rescheduling
/// on every return to the app keeps it right after travel.
class LocalNotificationsReminderScheduler implements ReminderScheduler {
  /// Creates the scheduler.
  LocalNotificationsReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    this._now = SystemClock.nowInstant,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The current local instant; a parameter so tests can fix it.
  final DateTime Function() _now;
  Future<void>? _initialised;

  Future<void> _ensureInitialised() => _initialised ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          // Permission is asked for when she turns a reminder on, not at
          // launch: an unexplained prompt on first open is how permissions
          // get refused.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      )
      .then((_) {});

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialised();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  @override
  Future<void> replaceAll(
    List<PlannedReminder> reminders, {
    required String text,
    required String channelName,
  }) async {
    await _ensureInitialised();
    await _plugin.cancelAll();

    final now = _now();
    final details = NotificationDetails(
      iOS: const DarwinNotificationDetails(),
      android: AndroidNotificationDetails(
        'reminders',
        channelName,
        // Nothing of hers on the lock screen, even in the private preview
        // Android shows before unlocking.
        visibility: NotificationVisibility.private,
      ),
    );

    var id = 0;
    for (final reminder in reminders) {
      final local = DateTime(
        reminder.day.year,
        reminder.day.month,
        reminder.day.day,
        reminder.hour,
        reminder.minute,
      );
      // Today's reminder time already gone: skip it rather than fire late.
      if (!local.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: id++,
        scheduledDate: tz.TZDateTime.from(local.toUtc(), tz.UTC),
        notificationDetails: details,
        // Inexact is fine for a reminder and needs no exact-alarm permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: text,
      );
    }
  }
}
