import '../../domain/models/cycle_date.dart';

/// One month laid out as whole weeks.
///
/// Pure date arithmetic on [CycleDate], with no [DateTime] anywhere: section 3
/// applies to a calendar grid as much as to an entry, and a grid built by adding
/// `Duration(days: 1)` can repeat or skip a day across a clock change. Every day
/// here comes from [CycleDate.addDays].
class MonthGrid {
  /// Creates a grid.
  const MonthGrid({
    required this.year,
    required this.month,
    required this.days,
  });

  /// The year the grid is centred on.
  final int year;

  /// The month the grid is centred on, 1 through 12.
  final int month;

  /// Every cell, in reading order, covering whole weeks.
  ///
  /// Includes the tail of the previous month and the head of the next, so the
  /// grid is rectangular. [isInMonth] tells them apart.
  final List<CycleDate> days;

  /// Whether [date] belongs to the month this grid is centred on.
  bool isInMonth(CycleDate date) => date.year == year && date.month == month;

  /// The grid split into rows of seven.
  List<List<CycleDate>> get weeks => [
    for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7),
  ];
}

/// Builds the grid for [month] of [year].
///
/// [firstDayOfWeekIndex] follows `MaterialLocalizations`: 0 is Sunday through 6
/// is Saturday. It is a parameter rather than a constant because the week starts
/// on Monday in German and on Sunday in American English, and a calendar that
/// gets that wrong is wrong in a way every user notices immediately.
MonthGrid monthGrid({
  required int year,
  required int month,
  required int firstDayOfWeekIndex,
}) {
  final first = CycleDate(year, month, 1);

  // CycleDate.weekday is ISO: 1 Monday through 7 Sunday. The Material index is
  // 0 Sunday through 6 Saturday. Convert, then walk back to the start of the
  // week the first of the month falls in.
  final firstAsMaterialIndex = first.weekday % 7;
  final lead = (firstAsMaterialIndex - firstDayOfWeekIndex + 7) % 7;
  final start = first.subtractDays(lead);

  final lastDay = CycleDate.lastDayOfMonth(year, month);
  final last = CycleDate(year, month, lastDay);
  final lastAsMaterialIndex = last.weekday % 7;
  final trail = (firstDayOfWeekIndex + 6 - lastAsMaterialIndex + 7) % 7;
  final end = last.addDays(trail);

  return MonthGrid(
    year: year,
    month: month,
    days: [for (var i = 0; i <= start.daysUntil(end); i++) start.addDays(i)],
  );
}
