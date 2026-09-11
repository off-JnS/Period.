import 'package:period/data/reminders.dart';
import 'package:period/domain/models/cycle_date.dart';
import 'package:period/domain/models/reminder_schedule.dart';
import 'package:period/domain/models/reminder_time.dart';

/// One call to [Reminders.applySchedule], kept so a test can read it back.
class AppliedSchedule {
  /// Records the call.
  const AppliedSchedule({
    required this.schedule,
    required this.today,
    required this.now,
    required this.title,
    required this.body,
  });

  /// What was asked for.
  final ReminderSchedule schedule;

  /// The day it was worked out from.
  final CycleDate today;

  /// The time of day it was worked out from.
  final ReminderTime now;

  /// The notification's title, so a test can check section 9's neutrality.
  final String title;

  /// The notification's body, for the same reason.
  final String body;
}

/// A [Reminders] that schedules nothing and remembers everything.
///
/// The real one reaches a platform plugin, which no test here can run. This
/// stands in its place so the flows around it -- turning the reminder on,
/// refusing the permission, skipping a day already logged -- are testable, and
/// so nothing in the suite has to pretend a notification appeared.
///
/// What it cannot tell you is whether a notification ever fires. See
/// docs/verification.md.
class FakeReminders implements Reminders {
  /// Creates reminders that grant permission, unless told otherwise.
  FakeReminders({this.granted = true});

  /// What [requestPermission] answers. False models a user, or an operating
  /// system, refusing notifications.
  bool granted;

  /// How many times permission was asked for.
  int permissionRequests = 0;

  /// Every call to [applySchedule], oldest first.
  final List<AppliedSchedule> applied = [];

  /// Every day passed to [skipToday], oldest first.
  final List<CycleDate> skipped = [];

  /// How many times everything was cancelled.
  int cancellations = 0;

  /// The last schedule applied, or null if none ever was.
  AppliedSchedule? get lastApplied => applied.isEmpty ? null : applied.last;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> applySchedule(
    ReminderSchedule schedule, {
    required CycleDate today,
    required ReminderTime now,
    required String title,
    required String body,
  }) async {
    applied.add(
      AppliedSchedule(
        schedule: schedule,
        today: today,
        now: now,
        title: title,
        body: body,
      ),
    );
  }

  @override
  Future<void> skipToday(
    ReminderSchedule schedule, {
    required CycleDate today,
    required String title,
    required String body,
  }) async {
    skipped.add(today);
  }

  @override
  Future<void> cancelAll() async => cancellations++;
}
