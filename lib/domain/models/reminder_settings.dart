import 'package:freezed_annotation/freezed_annotation.dart';

import 'cycle_date.dart';
import 'profile.dart';

part 'reminder_settings.freezed.dart';

/// How her pill pack is laid out. docs/cycle-logic.md §8.
///
/// Stored by name, so values may be added but never renamed.
enum PillPack {
  /// A pill every day, no break.
  everyDay(activeDays: 28),

  /// 21 days of pills, then a 7-day break.
  days21(activeDays: 21),

  /// 24 days of pills, then a 4-day break.
  days24(activeDays: 24);

  const PillPack({required this.activeDays});

  /// Days with a pill in each 28-day pack.
  final int activeDays;

  /// The length of one pack, break included.
  static const length = 28;

  /// Whether the pack has break days, so its first day matters.
  bool get hasBreak => activeDays < length;
}

/// Which contraception reminder belongs to a method, if any.
enum MethodReminder {
  /// A daily pill.
  pill,

  /// A vaginal ring.
  ring,

  /// A patch.
  patch,

  /// An injection.
  injection,

  /// An IUD or implant, replaced by a date.
  device;

  /// The reminder for [method], or null for one with nothing to remind of.
  static MethodReminder? of(ContraceptionMethod? method) => switch (method) {
    ContraceptionMethod.combinedPill ||
    ContraceptionMethod.progestinPill => pill,
    ContraceptionMethod.ring => ring,
    ContraceptionMethod.patch => patch,
    ContraceptionMethod.injection => injection,
    ContraceptionMethod.hormonalIud ||
    ContraceptionMethod.copperIud ||
    ContraceptionMethod.implant => device,
    ContraceptionMethod.none ||
    ContraceptionMethod.condom ||
    ContraceptionMethod.other ||
    null => null,
  };
}

/// Which reminders she asked for, and when. See docs/cycle-logic.md §8.
@freezed
abstract class ReminderSettings with _$ReminderSettings {
  const ReminderSettings._();

  const factory ReminderSettings({
    /// Remind her before the estimated window.
    @Default(false) bool periodComing,

    /// How many days before the window's first day, 1 to 5.
    @Default(ReminderSettings.defaultDaysBefore) int daysBefore,

    /// Remind her every day to log.
    @Default(false) bool dailyLog,

    /// The hour of day both cycle reminders arrive at, 0 to 23.
    @Default(9) int hour,

    /// The minute past [hour], 0 to 59.
    @Default(0) int minute,

    /// Remind her to take her pill every pill day.
    @Default(false) bool pill,

    /// The hour her pill reminder arrives at.
    @Default(21) int pillHour,

    /// The minute past [pillHour].
    @Default(0) int pillMinute,

    /// How her pack is laid out.
    @Default(PillPack.everyDay) PillPack pillPack,

    /// The first day of a pack, needed when [pillPack] has a break.
    CycleDate? pillPackStart,

    /// Remind her to take out and put in her ring.
    @Default(false) bool ring,

    /// The day she put the current ring in.
    CycleDate? ringInserted,

    /// Remind her to change her patch.
    @Default(false) bool patch,

    /// The day she put on the first patch of the current pack.
    CycleDate? patchStarted,

    /// Remind her of her next injection.
    @Default(false) bool injection,

    /// The day of her last injection.
    CycleDate? injectionLast,

    /// Weeks between injections, as she was told.
    @Default(ReminderSettings.defaultInjectionWeeks) int injectionWeeks,

    /// Remind her to have her IUD or implant replaced.
    @Default(false) bool device,

    /// The day it should be replaced by.
    CycleDate? deviceReplaceBy,

    /// How many weeks ahead to remind her.
    @Default(ReminderSettings.defaultDeviceWeeksBefore) int deviceWeeksBefore,

    /// The hour the ring, patch, injection and device reminders arrive at.
    @Default(9) int methodHour,

    /// The minute past [methodHour].
    @Default(0) int methodMinute,
  }) = _ReminderSettings;

  /// The default lead time before the estimated window.
  static const defaultDaysBefore = 2;

  /// The shortest lead time offered.
  static const minDaysBefore = 1;

  /// The longest lead time offered.
  static const maxDaysBefore = 5;

  /// The default and range of weeks between injections.
  static const defaultInjectionWeeks = 12;
  static const minInjectionWeeks = 4;
  static const maxInjectionWeeks = 14;

  /// How long before a replacement she may be reminded, in weeks.
  static const deviceWeeksOptions = [1, 2, 4, 8];
  static const defaultDeviceWeeksBefore = 4;

  /// Whether the reminder for [kind] is switched on.
  bool methodOn(MethodReminder kind) => switch (kind) {
    MethodReminder.pill => pill,
    MethodReminder.ring => ring,
    MethodReminder.patch => patch,
    MethodReminder.injection => injection,
    MethodReminder.device => device,
  };

  /// Whether any reminder is on, and so whether notifications are needed.
  bool get anyEnabled =>
      periodComing || dailyLog || pill || ring || patch || injection || device;
}
