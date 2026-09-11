import '../domain/models/clock.dart';
import '../domain/models/cycle_date.dart';
import '../domain/models/reminder_time.dart';

/// The only place in the app that reads the system clock.
///
/// CLAUDE.md section 3 permits a single `DateTime.now()`. This is it. If you are
/// about to add another one somewhere else, take the date as a parameter instead
/// and let the caller pass `clock.today()`.
///
/// The instant is read for its local year, month and day and then discarded, so
/// no timestamp, offset or epoch value reaches the domain or the database. Local
/// is deliberate: "today" means the day it is where the user is standing, so
/// crossing a timezone changes which day new entries land on, without moving any
/// entry already recorded.
class SystemClock implements Clock {
  /// Creates a clock backed by the device's own calendar.
  const SystemClock();

  @override
  CycleDate today() {
    final now = DateTime.now();
    return CycleDate(now.year, now.month, now.day);
  }

  @override
  ReminderTime timeOfDay() {
    final now = DateTime.now();
    // Hour and minute, local, and nothing else. The seconds, the date and the
    // offset are all discarded here rather than carried further.
    return ReminderTime(now.hour, now.minute);
  }
}
