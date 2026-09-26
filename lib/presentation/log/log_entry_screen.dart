import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/symptom.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../theme.dart';
import 'entry_labels.dart';
import 'temperature.dart';

/// Identifies the note field, the sheet's last text field, for tests.
const noteFieldKey = ValueKey('noteField');

/// What the user recorded on one day, on its way back to the caller.
///
/// The period start is carried alongside the entry rather than on it, because
/// that is how the two are stored: a period start is a row in its own table, and
/// `DayEntry` deliberately has no field for it. Section 4 is the reason -- the
/// start dates are the source of truth every estimate is computed from, so they
/// are not a property of a log entry that could be edited away by accident.
class LogEntryDraft {
  /// Creates the draft.
  const LogEntryDraft({required this.entry, required this.isPeriodStart});

  /// The day's entry, with whatever the user filled in.
  final DayEntry entry;

  /// Whether the user marked this day as the first day of a period.
  final bool isPeriodStart;
}

/// What the log screen was closed with.
///
/// A sealed result rather than a nullable draft, so the caller cannot confuse
/// "deleted everything for this day" with "changed nothing and backed out".
sealed class LogEntryResult {
  const LogEntryResult();
}

/// The user saved the day.
class LogEntrySaved extends LogEntryResult {
  /// Creates the result.
  const LogEntrySaved(this.draft);

  /// What to write.
  final LogEntryDraft draft;
}

/// The user deleted everything logged on the day.
class LogEntryDeleted extends LogEntryResult {
  /// Creates the result.
  const LogEntryDeleted(this.date);

  /// The day to clear.
  final CycleDate date;
}

/// Records what happened on one calendar day.
///
/// Presentation only: it takes the day's stored state, collects edits, and pops
/// a [LogEntryResult]. It never touches the database, which keeps every state --
/// a fresh day, a day being corrected, a day being cleared -- reachable in a
/// widget test without one.
class LogEntryScreen extends StatefulWidget {
  /// Creates the screen.
  const LogEntryScreen({
    required this.date,
    required this.today,
    this.entry,
    this.isPeriodStart = false,
    this.offerPill = false,
    super.key,
  });

  /// Whether to show the "pill taken" switch: only in the hormonal
  /// contraception mode, where it means something. A pill already logged on
  /// this day is kept either way.
  final bool offerPill;

  /// The day being logged.
  final CycleDate date;

  /// The day it is now, used as the latest day the picker will offer.
  ///
  /// Passed in rather than read here: section 3 allows one `DateTime.now()` in
  /// the whole app, and it is not this file.
  final CycleDate today;

  /// What was already logged on [date], or null for a day with nothing on it.
  final DayEntry? entry;

  /// Whether [date] is already marked as a period start.
  final bool isPeriodStart;

  @override
  State<LogEntryScreen> createState() => _LogEntryScreenState();
}

class _LogEntryScreenState extends State<LogEntryScreen> {
  late CycleDate _date = widget.date;
  late bool _isPeriodStart = widget.isPeriodStart;
  late FlowIntensity? _flow = widget.entry?.flow;
  late Set<String> _symptomKeys = {
    for (final symptom in widget.entry?.symptoms ?? const <Symptom>{})
      symptom.key,
  };

  /// The temperature as typed. Filled in [didChangeDependencies], once the
  /// locale is known, so a stored 3645 shows as "36,45" in German.
  final TextEditingController _temperature = TextEditingController();
  String _initialTemperatureText = '';
  bool _temperatureFilled = false;

  /// Set when Save was tapped with a temperature that could not be accepted.
  bool _temperatureInvalid = false;

  late final TextEditingController _note = TextEditingController(
    text: widget.entry?.note ?? '',
  )..addListener(_noteChanged);

  /// What the form held when it opened, to tell an edit from a look.
  late final Set<String> _initialSymptomKeys = {..._symptomKeys};

  /// The last value sent up in an [UnsavedChangesNotification].
  bool _reportedUnsaved = false;

  /// Whether leaving now would lose something she entered.
  ///
  /// Compared against what the form opened with, not "touched": toggling a
  /// chip on and back off again is not a change worth asking about.
  bool get _hasUnsavedChanges =>
      _date != widget.date ||
      _isPeriodStart != widget.isPeriodStart ||
      _flow != widget.entry?.flow ||
      _symptomKeys.length != _initialSymptomKeys.length ||
      !_symptomKeys.containsAll(_initialSymptomKeys) ||
      _note.text.trim() != (widget.entry?.note ?? '').trim() ||
      _temperature.text.trim() != _initialTemperatureText;

  void _temperatureChanged() {
    // The warning is about what was there when Save was tapped; editing is
    // her fixing it.
    if (_temperatureInvalid) setState(() => _temperatureInvalid = false);
    _noteChanged();
  }

  void _noteChanged() {
    if (_hasUnsavedChanges != _reportedUnsaved) setState(() {});
  }

  /// Whether the day held anything when the screen opened.
  ///
  /// Decides whether deleting is offered at all: there is nothing to delete on a
  /// day the user has not logged yet, and offering it would imply there is.
  bool get _hasSomethingStored => widget.entry != null || widget.isPeriodStart;

  @override
  void dispose() {
    _temperature
      ..removeListener(_temperatureChanged)
      ..dispose();
    _note
      ..removeListener(_noteChanged)
      ..dispose();
    super.dispose();
  }

  /// Adds or removes one logged key. Choosing a key in a single-choice group
  /// (discharge, sex) replaces whatever else in that group was chosen.
  void _toggle(String key, {required bool selected}) {
    setState(() {
      final next = {..._symptomKeys};
      if (selected) {
        for (final group in singleChoiceGroups) {
          if (group.contains(key)) next.removeAll(group);
        }
        next.add(key);
      } else {
        next.remove(key);
      }
      _symptomKeys = next;
    });
  }

  /// Tells the sheet around this screen whether it may be swiped away.
  void _reportUnsavedChanges() {
    final unsaved = _hasUnsavedChanges;
    if (unsaved == _reportedUnsaved) return;
    _reportedUnsaved = unsaved;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UnsavedChangesNotification(unsaved).dispatch(context);
    });
  }

  /// Asks before throwing away what she entered.
  ///
  /// An action sheet on iOS, where that is how "Discard Changes" is asked in
  /// Mail, Calendar and Notes; a dialog elsewhere.
  Future<void> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;

    final discard = isIos
        ? await showCupertinoModalPopup<bool>(
            context: context,
            builder: (context) => CupertinoActionSheet(
              title: Text(l10n.discardChangesQuestion),
              actions: [
                CupertinoActionSheetAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.discardChanges),
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.keepEditing),
              ),
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.discardChangesQuestion),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.keepEditing),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.discardChanges),
                ),
              ],
            ),
          );
    if (discard != true || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void toggled() => HapticFeedback.selectionClick();

    _reportUnsavedChanges();

    // Leaving with changes asks first -- through Cancel, and through the
    // system back gesture where there is one. Save and delete pop directly and
    // are not held up by this.
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: scheme.groupedBackground,
        // A sheet's bar, as in Calendar's new-event sheet: cancel on the left,
        // the confirming action on the right in bold, the title in between.
        appBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          backgroundColor: scheme.groupedBackground,
          border: null,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.cancel),
          ),
          middle: Text(l10n.entryTitle),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _save,
            child: Text(
              l10n.save,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
              ),
            ),
          ),
        ),
        // Scrollable for the same reason the Today screen is: at 200% text size
        // and in German this is considerably taller than a phone screen.
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
          children: [
            _DaySection(date: _date, onChangeDay: _pickDay),
            const SizedBox(height: 28),
            _PeriodSection(
              isPeriodStart: _isPeriodStart,
              onChanged: (value) {
                toggled();
                setState(() => _isPeriodStart = value);
              },
            ),
            const SizedBox(height: 28),
            _FlowSection(
              flow: _flow,
              onChanged: (value) {
                toggled();
                setState(() => _flow = value);
              },
            ),
            const SizedBox(height: 28),
            _ChipsSection(
              heading: l10n.symptomsHeading,
              keys: offeredSymptomKeys,
              selectedKeys: _symptomKeys,
              onToggle: (key, selected) {
                toggled();
                _toggle(key, selected: selected);
              },
            ),
            const SizedBox(height: 28),
            _ChipsSection(
              heading: l10n.moodHeading,
              keys: offeredMoodKeys,
              selectedKeys: _symptomKeys,
              onToggle: (key, selected) {
                toggled();
                _toggle(key, selected: selected);
              },
            ),
            const SizedBox(height: 28),
            _ChipsSection(
              heading: l10n.dischargeHeading,
              keys: offeredDischargeKeys,
              selectedKeys: _symptomKeys,
              singleChoice: true,
              footer: l10n.singleChoiceHint,
              onToggle: (key, selected) {
                toggled();
                _toggle(key, selected: selected);
              },
            ),
            const SizedBox(height: 28),
            _ChipsSection(
              heading: l10n.sexHeading,
              keys: offeredSexKeys,
              selectedKeys: _symptomKeys,
              singleChoice: true,
              footer: '${l10n.sexFooter} ${l10n.singleChoiceHint}',
              onToggle: (key, selected) {
                toggled();
                _toggle(key, selected: selected);
              },
            ),
            if (widget.offerPill) ...[
              const SizedBox(height: 28),
              _Group(
                heading: l10n.pillHeading,
                padding: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _symptomKeys.contains(pillTakenKey),
                  onChanged: (taken) {
                    toggled();
                    _toggle(pillTakenKey, selected: taken);
                  },
                  title: Text(l10n.pillTaken),
                ),
              ),
            ],
            const SizedBox(height: 28),
            _BodySignalsSection(
              temperature: _temperature,
              invalid: _temperatureInvalid,
              selectedKeys: _symptomKeys,
              onToggle: (key, selected) {
                toggled();
                _toggle(key, selected: selected);
              },
            ),
            const SizedBox(height: 28),
            _NoteSection(controller: _note),
            if (_hasSomethingStored) ...[
              const SizedBox(height: 28),
              // Destructive, so it sits alone at the bottom in red, well away
              // from Save, the way iOS places "Delete Event".
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _confirmDelete,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Center(
                      child: Text(
                        l10n.deleteEntry,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDay() async {
    // Far enough back to enter a history, and never past today: a period that
    // has not happened yet is not an observation, and letting one be logged
    // would feed a future start date straight into the estimates.
    final first = _toDateTime(widget.today.subtractDays(365 * 5));
    final last = _toDateTime(widget.today);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 280,
        color: Theme.of(context).colorScheme.groupedCard,
        child: SafeArea(
          top: false,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.date,
            initialDateTime: _toDateTime(_date),
            minimumDate: first,
            maximumDate: last,
            onDateTimeChanged: (picked) => setState(
              () => _date = CycleDate(picked.year, picked.month, picked.day),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.deleteEntryQuestion),
        content: Text(l10n.deleteEntryExplanation),
        actions: isIos
            ? [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.delete),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.delete),
                ),
              ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(LogEntryDeleted(_date));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_temperatureFilled) return;
    _temperatureFilled = true;
    final stored = widget.entry?.temperatureCentiCelsius;
    if (stored != null) {
      _initialTemperatureText = formatTemperatureNumber(
        stored,
        Localizations.localeOf(context).toLanguageTag(),
      );
      _temperature.text = _initialTemperatureText;
    }
    _temperature.addListener(_temperatureChanged);
  }

  void _save() {
    final int? temperature;
    switch (parseTemperature(_temperature.text)) {
      case ValidTemperature(:final centi):
        temperature = centi;
      case NoTemperature():
        temperature = null;
      case InvalidTemperature():
        // Refused, not stored and not silently dropped: she typed something,
        // so she is told why it cannot be kept.
        setState(() => _temperatureInvalid = true);
        return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(
      LogEntrySaved(
        LogEntryDraft(
          entry: DayEntry(
            date: _date,
            flow: _flow,
            // Empty is "not recorded", not an empty note. Section 5 wants a null
            // to mean the user did not write one.
            note: note.isEmpty ? null : note,
            temperatureCentiCelsius: temperature,
            symptoms: {for (final key in _symptomKeys) Symptom(key: key)},
          ),
          isPeriodStart: _isPeriodStart,
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.date, required this.onChangeDay});

  final CycleDate date;
  final VoidCallback onChangeDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatted = DateFormat.yMMMd(locale)
        .format(DateTime(date.year, date.month, date.day));

    // A label and a tinted date pill, as the date row in Calendar or Reminders.
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.entryDateHeading,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            Semantics(
              button: true,
              hint: l10n.changeDay,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                // 44pt tall: Apple's minimum touch target.
                minimumSize: const Size(44, 44),
                color: scheme.groupedBackground,
                borderRadius: BorderRadius.circular(8),
                onPressed: onChangeDay,
                child: Text(
                  formatted,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSection extends StatelessWidget {
  const _PeriodSection({required this.isPeriodStart, required this.onChanged});

  final bool isPeriodStart;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Group(
      heading: l10n.periodHeading,
      footer: l10n.periodStartExplanation,
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        value: isPeriodStart,
        onChanged: onChanged,
        title: Text(l10n.periodStartedThisDay),
      ),
    );
  }
}

class _FlowSection extends StatelessWidget {
  const _FlowSection({required this.flow, required this.onChanged});

  final FlowIntensity? flow;
  final ValueChanged<FlowIntensity?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // "Not recorded" is an option rather than the absence of one, so a user who
    // tapped a value by mistake has a way back to having said nothing. It is a
    // different fact from `none`, which means she looked and there was no
    // bleeding.
    return _Group(
      heading: l10n.flowHeading,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text(l10n.flowNotRecorded),
            selected: flow == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final value in FlowIntensity.values)
            ChoiceChip(
              label: Text(flowLabel(l10n, value)),
              selected: flow == value,
              onSelected: (_) => onChanged(value),
            ),
        ],
      ),
    );
  }
}

/// A group of chips for keyed things to log: symptoms, moods, discharge, sex.
///
/// Multi-choice groups use filter chips; single-choice groups use choice
/// chips, where tapping the chosen one again clears it, so "not recorded" is
/// always reachable without a separate chip.
class _ChipsSection extends StatelessWidget {
  const _ChipsSection({
    required this.heading,
    required this.keys,
    required this.selectedKeys,
    required this.onToggle,
    this.singleChoice = false,
    this.footer,
  });

  final String heading;
  final List<String> keys;
  final Set<String> selectedKeys;
  final void Function(String key, bool selected) onToggle;
  final bool singleChoice;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Group(
      heading: heading,
      footer: footer,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final key in keys)
            if (symptomLabel(l10n, key) case final label?)
              singleChoice
                  ? ChoiceChip(
                      label: Text(label),
                      selected: selectedKeys.contains(key),
                      onSelected: (selected) => onToggle(key, selected),
                    )
                  : FilterChip(
                      label: Text(label),
                      selected: selectedKeys.contains(key),
                      onSelected: (selected) => onToggle(key, selected),
                    ),
        ],
      ),
    );
  }
}

/// Basal temperature and the ovulation test: recorded only
/// (docs/cycle-logic.md §9), which the footer says outright.
class _BodySignalsSection extends StatelessWidget {
  const _BodySignalsSection({
    required this.temperature,
    required this.invalid,
    required this.selectedKeys,
    required this.onToggle,
  });

  final TextEditingController temperature;
  final bool invalid;
  final Set<String> selectedKeys;
  final void Function(String key, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return _Group(
      heading: l10n.bodySignalsHeading,
      footer: l10n.bodySignalsFooter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.temperatureLabel,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: temperature,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    hintText: formatTemperatureNumber(3650, locale),
                    suffixText: '°C',
                  ),
                ),
              ),
            ],
          ),
          if (invalid)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.temperatureInvalid,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const Divider(height: 24),
          Text(l10n.ovulationTestLabel, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in offeredOvulationTestKeys)
                if (symptomLabel(l10n, key) case final label?)
                  ChoiceChip(
                    label: Text(label),
                    selected: selectedKeys.contains(key),
                    onSelected: (selected) => onToggle(key, selected),
                  ),
            ],
          ),
          const Divider(height: 24),
          Text(l10n.pregnancyTestLabel, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in offeredPregnancyTestKeys)
                if (symptomLabel(l10n, key) case final label?)
                  ChoiceChip(
                    label: Text(label),
                    selected: selectedKeys.contains(key),
                    onSelected: (selected) => onToggle(key, selected),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteSection extends StatelessWidget {
  const _NoteSection({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Group(
      heading: l10n.noteHeading,
      footer: l10n.noteStaysOnDevice,
      child: TextField(
        key: noteFieldKey,
        controller: controller,
        minLines: 4,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: l10n.noteHint),
      ),
    );
  }
}

/// An inset group as in Settings: a small heading above, the card, and an
/// optional explanation below. Every section is told apart by its heading, not
/// by spacing alone.
class _Group extends StatelessWidget {
  const _Group({
    required this.heading,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.all(16),
  });

  final String heading;
  final Widget child;
  final String? footer;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(heading),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
        if (footer case final text?) GroupFooter(text),
      ],
    );
  }
}

/// Shows [screen] as an iOS sheet over the current screen.
///
/// A sheet rather than a pushed page: logging a day is a short task the user
/// finishes or cancels and returns from, which is what the HIG reserves sheets
/// for. It can be dragged down to cancel.
///
/// Once something has been changed, the sheet stops responding to the swipe:
/// a swipe would drop the changes without asking, and Cancel is there to ask.
/// This is iOS's own rule for sheets holding edits.
Future<LogEntryResult?> showLogEntrySheet(
  BuildContext context,
  LogEntryScreen screen,
) {
  late final _LogEntrySheetRoute route;
  route = _LogEntrySheetRoute(
    // The sheet's scroll controller is handed to the form's list, so dragging
    // down from the top of the list dismisses the sheet as it does in iOS.
    scrollableBuilder: (context, controller) =>
        NotificationListener<UnsavedChangesNotification>(
          onNotification: (notification) {
            route.allowDrag(!notification.hasUnsavedChanges);
            return true;
          },
          child: PrimaryScrollController(controller: controller, child: screen),
        ),
  );
  // The root navigator, as showCupertinoSheet does, so the screen behind
  // animates back as the sheet comes up.
  return Navigator.of(context, rootNavigator: true).push(route);
}

/// Sent up from [LogEntryScreen] whenever it gains or loses unsaved changes.
class UnsavedChangesNotification extends Notification {
  /// Creates the notification.
  const UnsavedChangesNotification(this.hasUnsavedChanges);

  /// Whether leaving now would lose something.
  final bool hasUnsavedChanges;
}

/// An iOS sheet whose swipe-to-dismiss can be switched off while it is open.
class _LogEntrySheetRoute extends CupertinoSheetRoute<LogEntryResult> {
  _LogEntrySheetRoute({required super.scrollableBuilder});

  bool _dragAllowed = true;

  // Overrides the fixed field so the answer can change while the sheet is up.
  @override
  bool get enableDrag => _dragAllowed;

  /// Switches swipe-to-dismiss on or off.
  ///
  /// The route hands [enableDrag] to its transition as a plain value when the
  /// transition is built, so changing it also has to rebuild the route.
  void allowDrag(bool allowed) {
    if (allowed == _dragAllowed) return;
    _dragAllowed = allowed;
    changedInternalState();
  }
}

DateTime _toDateTime(CycleDate date) =>
    DateTime(date.year, date.month, date.day);
