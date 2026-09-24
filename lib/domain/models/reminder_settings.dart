import 'package:freezed_annotation/freezed_annotation.dart';

part 'reminder_settings.freezed.dart';

/// Which reminders she asked for, and when. See docs/cycle-logic.md §8.
@freezed
abstract class ReminderSettings with _$ReminderSettings {
  const ReminderSettings._();

  const factory ReminderSettings({
    /// Remind her before the estimated window opens.
    @Default(false) bool periodComing,

    /// How many days before the window's first day, 1 to 5.
    @Default(ReminderSettings.defaultDaysBefore) int daysBefore,

    /// Remind her every day to log.
    @Default(false) bool dailyLog,

    /// The hour of day both reminders arrive at, 0 to 23.
    @Default(9) int hour,

    /// The minute past [hour], 0 to 59.
    @Default(0) int minute,
  }) = _ReminderSettings;

  /// The default lead time before the estimated window.
  static const defaultDaysBefore = 2;

  /// The shortest lead time offered.
  static const minDaysBefore = 1;

  /// The longest lead time offered.
  static const maxDaysBefore = 5;

  /// Whether any reminder is on, and so whether notifications are needed.
  bool get anyEnabled => periodComing || dailyLog;
}
