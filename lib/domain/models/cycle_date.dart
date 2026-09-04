/// A calendar day: year, month and day, with no time, timezone or UTC offset.
///
/// This is the only date type in the domain. See CLAUDE.md section 3.
///
/// Every operation is integer arithmetic on a day number. There is deliberately
/// no [DateTime] and no [Duration] anywhere in this file: a calendar day is not
/// a point in time, so there is no instant to shift and no DST boundary to cross.
/// Adding `Duration(days: 1)` to a local [DateTime] does not reliably advance one
/// calendar day; [addDays] always does.
///
/// Converting from the system clock happens in exactly one place outside the
/// domain — `SystemClock` in `lib/data/system_clock.dart`.
class CycleDate implements Comparable<CycleDate> {
  /// The proleptic Gregorian year.
  final int year;

  /// The month, 1 (January) through 12 (December).
  final int month;

  /// The day of the month, 1 through the real length of that month.
  final int day;

  /// Creates a calendar day, rejecting any combination that is not a real date.
  ///
  /// `CycleDate(2023, 2, 29)` throws — 2023 is not a leap year. This is checked
  /// rather than normalised on purpose: silently turning an impossible date into
  /// a neighbouring one is how an entry ends up on the wrong day.
  CycleDate(this.year, this.month, this.day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    final lastDay = lastDayOfMonth(year, month);
    if (day < 1 || day > lastDay) {
      throw ArgumentError.value(
        day,
        'day',
        'must be between 1 and $lastDay for $year-$month',
      );
    }
  }

  /// Whether [year] is a leap year in the proleptic Gregorian calendar.
  ///
  /// Note the century rule: 1900 is not a leap year, 2000 is.
  static bool isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  /// The number of days in [month] of [year].
  static int lastDayOfMonth(int year, int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be between 1 and 12');
    }
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && isLeapYear(year)) return 29;
    return lengths[month - 1];
  }

  /// Days since the epoch 1970-01-01, which is day 0. Negative before it.
  ///
  /// Howard Hinnant's `days_from_civil`, which is exact for every proleptic
  /// Gregorian date and uses only integer operations.
  int get _dayNumber => _daysFromCivil(year, month, day);

  static int _daysFromCivil(int y, int m, int d) {
    final shiftedYear = m <= 2 ? y - 1 : y;
    final era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) ~/ 400;
    final yearOfEra = shiftedYear - era * 400; // [0, 399]
    final dayOfYear =
        (153 * (m + (m > 2 ? -3 : 9)) + 2) ~/ 5 + d - 1; // [0, 365]
    final dayOfEra =
        yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
    return era * 146097 + dayOfEra - 719468;
  }

  /// The inverse of [_daysFromCivil]: Hinnant's `civil_from_days`.
  static CycleDate _fromDayNumber(int dayNumber) {
    final z = dayNumber + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final dayOfEra = z - era * 146097; // [0, 146096]
    final yearOfEra =
        (dayOfEra -
            dayOfEra ~/ 1460 +
            dayOfEra ~/ 36524 -
            dayOfEra ~/ 146096) ~/
        365; // [0, 399]
    final year = yearOfEra + era * 400;
    final dayOfYear =
        dayOfEra - (365 * yearOfEra + yearOfEra ~/ 4 - yearOfEra ~/ 100);
    final mp = (5 * dayOfYear + 2) ~/ 153; // [0, 11]
    final day = dayOfYear - (153 * mp + 2) ~/ 5 + 1; // [1, 31]
    final month = mp + (mp < 10 ? 3 : -9); // [1, 12]
    return CycleDate(month <= 2 ? year + 1 : year, month, day);
  }

  /// The calendar day [days] after this one. Negative values go backwards.
  ///
  /// Always advances whole calendar days, including across month ends, year
  /// ends, leap days and the days on which clocks change.
  CycleDate addDays(int days) => _fromDayNumber(_dayNumber + days);

  /// The calendar day [days] before this one.
  CycleDate subtractDays(int days) => addDays(-days);

  /// The number of calendar days from this day to [other].
  ///
  /// Positive when [other] is later, negative when earlier, zero when equal.
  int daysUntil(CycleDate other) => other._dayNumber - _dayNumber;

  /// The day of the week, 1 (Monday) through 7 (Sunday), matching ISO 8601.
  int get weekday {
    // Day 0 (1970-01-01) was a Thursday, which is ISO weekday 4.
    final shifted = (_dayNumber + 3) % 7;
    return (shifted < 0 ? shifted + 7 : shifted) + 1;
  }

  /// Whether this day falls before [other].
  bool isBefore(CycleDate other) => _dayNumber < other._dayNumber;

  /// Whether this day falls after [other].
  bool isAfter(CycleDate other) => _dayNumber > other._dayNumber;

  @override
  int compareTo(CycleDate other) => _dayNumber.compareTo(other._dayNumber);

  /// This day as `YYYY-MM-DD`, zero padded.
  ///
  /// For persistence and backup files only. User-facing dates are formatted with
  /// `intl` in the presentation layer, so they follow the reader's locale.
  String toIso8601() {
    final y = year.abs().toString().padLeft(4, '0');
    final sign = year < 0 ? '-' : '';
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$sign$y-$m-$d';
  }

  /// Parses `YYYY-MM-DD` as written by [toIso8601].
  ///
  /// Throws [FormatException] on anything else, including a well-formed string
  /// that is not a real date such as `2023-02-29`.
  static CycleDate parseIso8601(String value) {
    final match = RegExp(r'^(-?\d{4,})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('Expected a YYYY-MM-DD calendar date', value);
    }
    try {
      return CycleDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } on ArgumentError catch (error) {
      throw FormatException(
        'Not a real calendar date: ${error.message}',
        value,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CycleDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'CycleDate(${toIso8601()})';
}
