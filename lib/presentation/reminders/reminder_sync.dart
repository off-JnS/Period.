import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../data/reminders/reminder_scheduler.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/logic/reminders.dart';
import '../../domain/models/clock.dart';

/// Keeps the scheduled reminders in step with what is stored.
///
/// Everything a reminder depends on -- the period starts, the mode, her
/// reminder settings, even the language of its one word -- can change, and
/// nothing about a reminder is stored (§4). So rather than patching the
/// schedule, every change rebuilds it from scratch.
class ReminderSync {
  /// Creates the sync.
  ReminderSync({
    required this.logDao,
    required this.settingsDao,
    required this.scheduler,
    required this.clock,
  });

  /// Reads the period starts the estimate is computed from.
  final LogDao logDao;

  /// Reads the mode and the reminder settings.
  final SettingsDao settingsDao;

  /// Where the reminders go.
  final ReminderScheduler scheduler;

  /// Supplies today.
  final Clock clock;

  Future<void> _last = Future.value();

  /// Asks the device for permission to notify.
  Future<bool> requestPermission() => scheduler.requestPermission();

  /// Rebuilds the schedule. Calls queue behind each other, so two quick
  /// changes cannot interleave and leave a half-built schedule.
  ///
  /// Never throws. A reminder that could not be scheduled is not worth
  /// breaking the screen that asked, and there is no crash reporter to tell.
  Future<void> sync({required String text, required String channelName}) =>
      _last = _last.then(
        (_) => _sync(text: text, channelName: channelName).catchError((_) {}),
      );

  Future<void> _sync({
    required String text,
    required String channelName,
  }) async {
    final reminders = await settingsDao.reminderSettings();

    var planned = const <PlannedReminder>[];
    if (reminders.anyEnabled) {
      final today = clock.today();
      final starts = await logDao.allPeriodStarts();
      final cycle = await settingsDao.cycleSettings();
      final profile = await settingsDao.profile(currentYear: today.year);
      planned = planReminders(
        settings: reminders,
        prediction: predictNextPeriod(periodStarts: starts, settings: cycle),
        today: today,
        method: profile.contraception,
      );
    }

    await scheduler.replaceAll(planned, text: text, channelName: channelName);
  }
}
