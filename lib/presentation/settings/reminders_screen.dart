import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/logic/reminders.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/reminder_settings.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../profile/profile_labels.dart';
import '../theme.dart';

/// Keys for the reminders page, so tests can reach its rows without text.
abstract final class RemindersKeys {
  /// The switch for her method's reminder.
  static const methodSwitch = ValueKey('reminders.method');

  /// The row with her method's date.
  static const methodDate = ValueKey('reminders.methodDate');

  /// The date wheel in its popup.
  static const dateWheel = ValueKey('reminders.dateWheel');
}

/// Every reminder, opened from Settings: the cycle's two, and the one for
/// the contraception in her profile. docs/cycle-logic.md §8.
///
/// Presentation only: it renders [reminders] and reports every change through
/// [onChanged], as Settings does.
class RemindersScreen extends StatelessWidget {
  /// Creates the screen.
  const RemindersScreen({
    required this.reminders,
    required this.method,
    required this.today,
    required this.onChanged,
    this.blocked = false,
    this.backLabel,
    super.key,
  });

  /// What is set.
  final ReminderSettings reminders;

  /// Her contraception, from her profile, or null if she has not said.
  final ContraceptionMethod? method;

  /// Today, for the date wheels' limits and the list of what is coming.
  final CycleDate today;

  /// Called with the whole new settings on any change.
  final ValueChanged<ReminderSettings> onChanged;

  /// Whether notifications were refused, so reminders cannot arrive.
  final bool blocked;

  /// Settings' title, for the back button.
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = MethodReminder.of(method);
    final coming = kind == null
        ? const <PlannedReminder>[]
        : planMethodReminders(
            settings: reminders,
            today: today,
            method: method,
          ).take(5).toList();

    return GroupedPage(
      title: l10n.remindersHeading,
      backLabel: backLabel,
      children: [
        if (blocked) ...[
          _Notice(l10n.remindersBlocked),
          const SizedBox(height: 20),
        ],
        GroupHeader(l10n.remindersCycleHeading),
        _CycleCard(reminders: reminders, onChanged: onChanged),
        GroupFooter(l10n.remindersFooter),
        const SizedBox(height: 28),
        GroupHeader(
          method == null
              ? l10n.contraceptionLabel
              : '${l10n.contraceptionLabel}: ${methodLabel(l10n, method!)}',
        ),
        switch (kind) {
          null => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                method == null
                    ? l10n.remindersNoMethod
                    : l10n.remindersNothingForMethod(
                        methodLabel(l10n, method!),
                      ),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          final kind => _MethodCard(
            kind: kind,
            reminders: reminders,
            today: today,
            onChanged: onChanged,
          ),
        },
        if (kind != null) GroupFooter(_methodFooter(l10n, kind)),
        if (coming.isNotEmpty) ...[
          const SizedBox(height: 28),
          GroupHeader(l10n.remindersComingUp),
          _ComingUp(reminders: coming, today: today),
          GroupFooter(l10n.remindersComingUpFooter),
        ],
      ],
    );
  }

  String _methodFooter(AppLocalizations l10n, MethodReminder kind) =>
      switch (kind) {
        MethodReminder.pill => l10n.reminderPillFooter,
        MethodReminder.ring => l10n.reminderRingFooter,
        MethodReminder.patch => l10n.reminderPatchFooter,
        MethodReminder.injection => l10n.reminderInjectionFooter,
        MethodReminder.device => l10n.reminderDeviceFooter,
      };
}

/// A tinted line at the top, for something she needs to act on.
class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.bell_slash, size: 20, color: scheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// The period and daily-log reminders, and their time.
class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.reminders, required this.onChanged});

  final ReminderSettings reminders;
  final ValueChanged<ReminderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: reminders.periodComing,
            onChanged: (value) =>
                onChanged(reminders.copyWith(periodComing: value)),
            title: Text(l10n.reminderPeriodComing),
          ),
          if (reminders.periodComing) ...[
            const Divider(indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.reminderDaysBefore,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  // Five plain numbers: short enough for a segmented control
                  // at any text size, where a wheel would be overkill.
                  _Segments<int>(
                    value: reminders.daysBefore,
                    options: {
                      for (
                        var days = ReminderSettings.minDaysBefore;
                        days <= ReminderSettings.maxDaysBefore;
                        days++
                      )
                        days: '$days',
                    },
                    onChanged: (days) =>
                        onChanged(reminders.copyWith(daysBefore: days)),
                  ),
                ],
              ),
            ),
          ],
          const Divider(indent: 16),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: reminders.dailyLog,
            onChanged: (value) =>
                onChanged(reminders.copyWith(dailyLog: value)),
            title: Text(l10n.reminderDailyLog),
          ),
          if (reminders.periodComing || reminders.dailyLog) ...[
            const Divider(indent: 16),
            _TimeRow(
              hour: reminders.hour,
              minute: reminders.minute,
              onChanged: (hour, minute) =>
                  onChanged(reminders.copyWith(hour: hour, minute: minute)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The reminder for her method: its switch, and once on, its date, its
/// details and its time.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.kind,
    required this.reminders,
    required this.today,
    required this.onChanged,
  });

  final MethodReminder kind;
  final ReminderSettings reminders;
  final CycleDate today;
  final ValueChanged<ReminderSettings> onChanged;

  ReminderSettings _switched(bool on) => switch (kind) {
    MethodReminder.pill => reminders.copyWith(pill: on),
    MethodReminder.ring => reminders.copyWith(ring: on),
    MethodReminder.patch => reminders.copyWith(patch: on),
    MethodReminder.injection => reminders.copyWith(injection: on),
    MethodReminder.device => reminders.copyWith(device: on),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final on = reminders.methodOn(kind);

    final title = switch (kind) {
      MethodReminder.pill => l10n.reminderPill,
      MethodReminder.ring => l10n.reminderRing,
      MethodReminder.patch => l10n.reminderPatch,
      MethodReminder.injection => l10n.reminderInjection,
      MethodReminder.device => l10n.reminderDevice,
    };

    Widget date({
      required String label,
      required CycleDate? value,
      required CycleDate first,
      required CycleDate last,
      required ValueChanged<CycleDate> onPicked,
    }) => _DateRow(
      key: RemindersKeys.methodDate,
      label: label,
      value: value,
      first: first,
      last: last,
      initial: value ?? (today.isAfter(last) ? last : today),
      onPicked: onPicked,
    );

    final details = <Widget>[
      switch (kind) {
        MethodReminder.pill => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.reminderPillPack, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  _Segments<PillPack>(
                    value: reminders.pillPack,
                    options: {
                      PillPack.everyDay: l10n.pillPackEveryDay,
                      PillPack.days21: l10n.pillPack21,
                      PillPack.days24: l10n.pillPack24,
                    },
                    onChanged: (pack) => onChanged(
                      reminders.copyWith(
                        pillPack: pack,
                        // A pack with a break needs its first day; today is
                        // the likeliest, and she can change it below.
                        pillPackStart: pack.hasBreak
                            ? reminders.pillPackStart ?? today
                            : reminders.pillPackStart,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (reminders.pillPack.hasBreak) ...[
              const Divider(indent: 16),
              date(
                label: l10n.reminderPillPackStart,
                value: reminders.pillPackStart,
                first: today.subtractDays(90),
                last: today.addDays(PillPack.length - 1),
                onPicked: (day) =>
                    onChanged(reminders.copyWith(pillPackStart: day)),
              ),
            ],
          ],
        ),
        MethodReminder.ring => date(
          label: l10n.reminderRingInserted,
          value: reminders.ringInserted,
          first: today.subtractDays(120),
          last: today,
          onPicked: (day) => onChanged(reminders.copyWith(ringInserted: day)),
        ),
        MethodReminder.patch => date(
          label: l10n.reminderPatchStarted,
          value: reminders.patchStarted,
          first: today.subtractDays(120),
          last: today,
          onPicked: (day) => onChanged(reminders.copyWith(patchStarted: day)),
        ),
        MethodReminder.injection => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            date(
              label: l10n.reminderInjectionLast,
              value: reminders.injectionLast,
              first: today.subtractDays(365),
              last: today,
              onPicked: (day) =>
                  onChanged(reminders.copyWith(injectionLast: day)),
            ),
            const Divider(indent: 16),
            _Stepper(
              label: l10n.reminderInjectionEvery,
              value: reminders.injectionWeeks,
              min: ReminderSettings.minInjectionWeeks,
              max: ReminderSettings.maxInjectionWeeks,
              format: (weeks) => l10n.reminderWeeks(weeks),
              onChanged: (weeks) =>
                  onChanged(reminders.copyWith(injectionWeeks: weeks)),
            ),
          ],
        ),
        MethodReminder.device => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            date(
              label: l10n.reminderDeviceReplaceBy,
              value: reminders.deviceReplaceBy,
              first: today,
              // IUDs and implants are fitted for up to about a decade.
              last: today.addDays(365 * 12),
              onPicked: (day) =>
                  onChanged(reminders.copyWith(deviceReplaceBy: day)),
            ),
            const Divider(indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.reminderDeviceWeeksBefore,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  _Segments<int>(
                    value: reminders.deviceWeeksBefore,
                    options: {
                      for (final weeks in ReminderSettings.deviceWeeksOptions)
                        weeks: l10n.reminderWeeksShort(weeks),
                    },
                    onChanged: (weeks) =>
                        onChanged(reminders.copyWith(deviceWeeksBefore: weeks)),
                  ),
                ],
              ),
            ),
          ],
        ),
      },
      const Divider(indent: 16),
      if (kind == MethodReminder.pill)
        _TimeRow(
          hour: reminders.pillHour,
          minute: reminders.pillMinute,
          onChanged: (hour, minute) =>
              onChanged(reminders.copyWith(pillHour: hour, pillMinute: minute)),
        )
      else
        _TimeRow(
          hour: reminders.methodHour,
          minute: reminders.methodMinute,
          onChanged: (hour, minute) => onChanged(
            reminders.copyWith(methodHour: hour, methodMinute: minute),
          ),
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              key: RemindersKeys.methodSwitch,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: on,
              onChanged: (value) => onChanged(_switched(value)),
              title: Text(title),
            ),
            if (on) ...[const Divider(indent: 16), ...details],
          ],
        ),
      ),
    );
  }
}

/// What the next few method reminders are for, and when: only here in the
/// app, never on the lock screen.
class _ComingUp extends StatelessWidget {
  const _ComingUp({required this.reminders, required this.today});

  final List<PlannedReminder> reminders;
  final CycleDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final materialL10n = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);

    String what(ReminderKind kind) => switch (kind) {
      ReminderKind.pill => l10n.reminderKindPill,
      ReminderKind.ringOut => l10n.reminderKindRingOut,
      ReminderKind.ringIn => l10n.reminderKindRingIn,
      ReminderKind.patchChange => l10n.reminderKindPatchChange,
      ReminderKind.patchOff => l10n.reminderKindPatchOff,
      ReminderKind.patchOn => l10n.reminderKindPatchOn,
      ReminderKind.injectionSoon => l10n.reminderKindInjectionSoon,
      ReminderKind.injectionDue => l10n.reminderKindInjectionDue,
      ReminderKind.deviceSoon => l10n.reminderKindDeviceSoon,
      ReminderKind.deviceDue => l10n.reminderKindDeviceDue,
      ReminderKind.periodComing => l10n.reminderPeriodComing,
      ReminderKind.dailyLog => l10n.reminderDailyLog,
    };

    return Card(
      child: Column(
        children: [
          for (final (index, reminder) in reminders.indexed) ...[
            if (index > 0) const Divider(indent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        what(reminder.kind),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      [
                        if (reminder.day == today)
                          l10n.todayTitle
                        else
                          // The year only once it is not this one: an IUD
                          // date can be years away.
                          (reminder.day.year == today.year
                                  ? DateFormat.MMMEd(locale)
                                  : DateFormat.yMMMEd(locale))
                              .format(
                                DateTime(
                                  reminder.day.year,
                                  reminder.day.month,
                                  reminder.day.day,
                                ),
                              ),
                        materialL10n.formatTimeOfDay(
                          TimeOfDay(
                            hour: reminder.hour,
                            minute: reminder.minute,
                          ),
                          alwaysUse24HourFormat: use24,
                        ),
                      ].join(', '),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A sliding segmented control, full width, one text per option.
class _Segments<T extends Object> extends StatelessWidget {
  const _Segments({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      thumbColor: scheme.groupedCard,
      backgroundColor: scheme.groupedBackground,
      onValueChanged: (next) {
        if (next != null && next != value) onChanged(next);
      },
      children: {
        for (final MapEntry(:key, value: text) in options.entries)
          key: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      },
    );
  }
}

/// A label, and a tinted value that opens a wheel.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final bool placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: '$label: $value',
            excludeSemantics: true,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 44),
              color: scheme.groupedBackground,
              borderRadius: BorderRadius.circular(8),
              onPressed: onTap,
              child: Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: placeholder ? scheme.onSurfaceVariant : scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A time of day, on a wheel in five-minute steps.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: hour, minute: minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return _PickerRow(
      label: l10n.reminderTime,
      value: time,
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    var pickedHour = hour;
    var pickedMinute = minute;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 280,
        color: Theme.of(context).colorScheme.groupedCard,
        child: SafeArea(
          top: false,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
            minuteInterval: 5,
            // A DateTime only as the wheel's starting position; the day part
            // is meaningless and nothing here is stored as a timestamp.
            initialDateTime: DateTime(2000, 1, 1, hour, minute - minute % 5),
            onDateTimeChanged: (picked) {
              pickedHour = picked.hour;
              pickedMinute = picked.minute;
            },
          ),
        ),
      ),
    );
    if (pickedHour != hour || pickedMinute != minute) {
      onChanged(pickedHour, pickedMinute);
    }
  }
}

/// A calendar day, on a wheel between [first] and [last], kept only when
/// she taps Done.
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.first,
    required this.last,
    required this.initial,
    required this.onPicked,
    super.key,
  });

  final String label;
  final CycleDate? value;
  final CycleDate first;
  final CycleDate last;
  final CycleDate initial;
  final ValueChanged<CycleDate> onPicked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final day = value;
    return _PickerRow(
      label: label,
      value: day == null
          ? l10n.reminderNotSet
          : DateFormat.yMMMd(locale).format(_dateTime(day)),
      placeholder: day == null,
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    var current = initial;
    var done = false;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Material(
          color: scheme.groupedCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 72),
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () {
                        done = true;
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        l10n.doneButton,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 216,
                  child: CupertinoDatePicker(
                    key: RemindersKeys.dateWheel,
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: _dateTime(initial),
                    minimumDate: _dateTime(first),
                    maximumDate: _dateTime(last),
                    onDateTimeChanged: (picked) => current = CycleDate(
                      picked.year,
                      picked.month,
                      picked.day,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (done && current != value) onPicked(current);
  }
}

/// A number with minus and plus, for a small range.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String Function(int value) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final down = value > min ? value - 1 : null;
    final up = value < max ? value + 1 : null;

    Widget button(IconData icon, int? next) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(40, 40),
      onPressed: next == null ? null : () => onChanged(next),
      child: Icon(icon, size: 22, color: next == null ? null : scheme.primary),
    );

    // One adjustable control for VoiceOver, swiped up and down, rather than
    // two unnamed buttons either side of a number.
    return Semantics(
      label: label,
      value: format(value),
      increasedValue: up == null ? null : format(up),
      decreasedValue: down == null ? null : format(down),
      onIncrease: up == null ? null : () => onChanged(up),
      onDecrease: down == null ? null : () => onChanged(down),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            button(CupertinoIcons.minus_circle, down),
            SizedBox(
              width: 92,
              child: Text(
                format(value),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            button(CupertinoIcons.plus_circle, up),
          ],
        ),
      ),
    );
  }
}

DateTime _dateTime(CycleDate day) => DateTime(day.year, day.month, day.day);
