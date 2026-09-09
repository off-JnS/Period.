/// A wall-clock time of day: hour and minute, with no date and no timezone.
///
/// The companion to [CycleDate], which is a calendar day with no time. Together
/// they say "20:00 on the 3rd" without ever being an instant — which is the
/// whole point, per docs/cycle-logic.md section 7. A reminder that knows its
/// wall time survives a daylight-saving change; one stored as an instant, or
/// advanced by twenty-four hours, does not.
///
/// Flutter's `TimeOfDay` is the obvious thing to reuse and cannot be: CLAUDE.md
/// section 2 forbids `domain/` importing Flutter, so this layer stays runnable
/// by `dart test` with no binding and no device.
///
/// There is deliberately no [DateTime] and no [Duration] in this file, for the
/// same reason there is none in `cycle_date.dart`.
class ReminderTime implements Comparable<ReminderTime> {
  /// The hour on a 24-hour clock, 0 through 23.
  final int hour;

  /// The minute, 0 through 59.
  final int minute;

  /// Creates a time of day, rejecting anything that is not one.
  ///
  /// Checked rather than wrapped on purpose: turning 24:00 into 00:00 silently
  /// moves a reminder to the previous midnight, a day earlier than intended.
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23, 'hour must be between 0 and 23'),
      assert(minute >= 0 && minute <= 59, 'minute must be between 0 and 59');

  /// Creates a time of day, throwing on values outside a real clock.
  ///
  /// The throwing counterpart to the const constructor's asserts, for values
  /// that arrive at runtime — from storage, or from a picker — where an assert
  /// does nothing in a release build.
  factory ReminderTime.checked(int hour, int minute) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'must be between 0 and 23');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(minute, 'minute', 'must be between 0 and 59');
    }
    return ReminderTime(hour, minute);
  }

  /// Minutes since midnight. The ordering this type compares on.
  int get minutesSinceMidnight => hour * 60 + minute;

  /// Whether this time falls before [other] on the same day.
  bool isBefore(ReminderTime other) =>
      minutesSinceMidnight < other.minutesSinceMidnight;

  /// Whether this time falls after [other] on the same day.
  bool isAfter(ReminderTime other) =>
      minutesSinceMidnight > other.minutesSinceMidnight;

  @override
  int compareTo(ReminderTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  /// This time as `HH:mm`, zero padded.
  ///
  /// For persistence only. A time shown to a person is formatted with `intl` in
  /// the presentation layer, because 20:00 and 8:00 PM are the same time and
  /// only one of them is right for a given reader.
  String toHhMm() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Parses `HH:mm` as written by [toHhMm].
  ///
  /// Throws [FormatException] on anything else, including a well-formed string
  /// that is not a real time such as `25:00`.
  static ReminderTime parseHhMm(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('Expected an HH:mm time of day', value);
    }
    try {
      return ReminderTime.checked(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Not a real time of day: ${error.message}', value);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReminderTime(${toHhMm()})';
}
