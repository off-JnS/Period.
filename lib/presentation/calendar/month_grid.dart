import '../../domain/models/cycle_date.dart';

/// One month laid out as whole weeks.
///
/// Pure calendar arithmetic over [CycleDate], so the grid can be reasoned about
/// and tested without building a widget. Layout rather than cycle logic, which
/// is why it lives here and not in `domain/logic`.
class MonthGrid {
  /// Builds the grid for [month], padded to whole weeks.
  ///
  /// [firstWeekday] is the locale's first day, 1 (Monday) through 7 (Sunday) --
  /// Germany starts on Monday, the United States on Sunday, and the calendar has
  /// to follow the reader rather than a hardcoded choice.
  factory MonthGrid.of(CycleDate month, {required int firstWeekday}) {
    if (firstWeekday < 1 || firstWeekday > 7) {
      throw ArgumentError.value(
        firstWeekday,
        'firstWeekday',
        'must be 1 (Monday) through 7 (Sunday)',
      );
    }

    final first = CycleDate(month.year, month.month, 1);
    final length = CycleDate.lastDayOfMonth(month.year, month.month);

    // How many days of the previous month to show before the 1st, so the grid
    // starts on the locale's first weekday.
    final lead = (first.weekday - firstWeekday + 7) % 7;
    final start = first.subtractDays(lead);

    // Whole weeks only: a ragged final row makes the grid harder to scan.
    final total = ((lead + length) / 7).ceil() * 7;

    return MonthGrid._(
      month: first,
      firstWeekday: firstWeekday,
      days: [for (var i = 0; i < total; i++) start.addDays(i)],
    );
  }

  const MonthGrid._({
    required this.month,
    required this.firstWeekday,
    required this.days,
  });

  /// The first day of the month this grid represents.
  final CycleDate month;

  /// The weekday this grid's rows begin on, 1 (Monday) through 7 (Sunday).
  ///
  /// Kept here rather than passed alongside the grid, so the column headings
  /// drawn above it cannot be computed from a different answer than the days
  /// beneath them. That mismatch shifts every label one column and looks
  /// entirely plausible.
  final int firstWeekday;

  /// Every cell, in order, including the padding days either side.
  final List<CycleDate> days;

  /// The cells grouped into weeks of seven.
  List<List<CycleDate>> get weeks => [
    for (var i = 0; i < days.length; i += 7) days.sublist(i, i + 7),
  ];

  /// Whether [date] belongs to this month rather than the padding.
  ///
  /// Padding days are shown so the weeks line up, but they are not this month's
  /// and are drawn faintly.
  bool isInMonth(CycleDate date) =>
      date.year == month.year && date.month == month.month;

  /// The month before this one, laid out the same way.
  MonthGrid previous() =>
      MonthGrid.of(month.subtractDays(1), firstWeekday: firstWeekday);

  /// The month after this one, laid out the same way.
  MonthGrid next() => MonthGrid.of(
    month.addDays(CycleDate.lastDayOfMonth(month.year, month.month)),
    firstWeekday: firstWeekday,
  );
}
