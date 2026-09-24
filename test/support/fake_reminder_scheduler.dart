import 'package:period/data/reminders/reminder_scheduler.dart';
import 'package:period/domain/logic/reminders.dart';

/// Records what would have been scheduled, and answers permission as told.
class FakeReminderScheduler implements ReminderScheduler {
  /// Whether the permission prompt is accepted.
  bool grants = true;

  /// How many times permission was asked for.
  int permissionRequests = 0;

  /// Every call to [replaceAll], oldest first.
  final List<List<PlannedReminder>> schedules = [];

  /// The text of the last schedule.
  String? lastText;

  /// The latest schedule, or null if nothing was ever scheduled.
  List<PlannedReminder>? get current =>
      schedules.isEmpty ? null : schedules.last;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grants;
  }

  @override
  Future<void> replaceAll(
    List<PlannedReminder> reminders, {
    required String text,
    required String channelName,
  }) async {
    schedules.add(List.of(reminders));
    lastText = text;
  }
}
