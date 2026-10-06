import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/symptom.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../theme.dart';
import 'entry_icons.dart';
import 'entry_labels.dart';
import 'temperature.dart';

/// Identifies the note field, the sheet's last text field, for tests.
const noteFieldKey = ValueKey('noteField');

/// The folded sections at the bottom of the log sheet.
enum EntryFold {
  /// Discharge.
  discharge,

  /// Sex.
  sex,

  /// Temperature and tests.
  bodySignals,
}

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

  /// The folded sections she has opened.
  final Set<EntryFold> _open = {};

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
          children: [
            // Which day, as a week to tap through: most entries are for
            // today or a day or two back, one tap away here.
            _Group(
              heading: l10n.entryDateHeading,
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
              child: _DayStrip(
                date: _date,
                today: widget.today,
                onSelect: (day) => setState(() => _date = day),
                onOpenWheel: _pickDay,
              ),
            ),
            const SizedBox(height: 24),
            _PeriodSection(
              flow: _flow,
              onFlowChanged: (value) => setState(() => _flow = value),
              isPeriodStart: _isPeriodStart,
              onPeriodStartChanged: (value) {
                setState(() => _isPeriodStart = value);
              },
            ),
            if (widget.offerPill) ...[
              const SizedBox(height: 24),
              _Group(
                heading: l10n.pillHeading,
                padding: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _symptomKeys.contains(pillTakenKey),
                  onChanged: (taken) {
                    _toggle(pillTakenKey, selected: taken);
                  },
                  title: Text(l10n.pillTaken),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _OptionsSection(
              heading: l10n.symptomsHeading,
              keys: offeredSymptomKeys,
              selectedKeys: _symptomKeys,
              onToggle: (key, selected) => _toggle(key, selected: selected),
            ),
            const SizedBox(height: 24),
            _OptionsSection(
              heading: l10n.moodHeading,
              keys: offeredMoodKeys,
              selectedKeys: _symptomKeys,
              onToggle: (key, selected) => _toggle(key, selected: selected),
            ),
            const SizedBox(height: 24),
            // Asked for less often, so folded away with what she chose shown
            // beside each name; one tap opens it.
            GroupHeader(l10n.entryMoreHeading),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _Fold(
                    heading: l10n.dischargeHeading,
                    summary: _chosen(offeredDischargeKeys),
                    open: _open.contains(EntryFold.discharge),
                    onToggle: () => _flip(EntryFold.discharge),
                    child: _Options(
                      keys: offeredDischargeKeys,
                      selectedKeys: _symptomKeys,
                      onToggle: (key, selected) {
                        _toggle(key, selected: selected);
                      },
                      footer: l10n.singleChoiceHint,
                    ),
                  ),
                  const Divider(indent: 16),
                  _Fold(
                    heading: l10n.sexHeading,
                    summary: _chosen(offeredSexKeys),
                    open: _open.contains(EntryFold.sex),
                    onToggle: () => _flip(EntryFold.sex),
                    child: _Options(
                      keys: offeredSexKeys,
                      selectedKeys: _symptomKeys,
                      onToggle: (key, selected) {
                        _toggle(key, selected: selected);
                      },
                      footer: '${l10n.sexFooter} ${l10n.singleChoiceHint}',
                    ),
                  ),
                  const Divider(indent: 16),
                  _Fold(
                    heading: l10n.bodySignalsHeading,
                    summary: [
                      if (_temperature.text.trim() case final t
                          when t.isNotEmpty)
                        '$t °C',
                      ?_chosen(offeredOvulationTestKeys),
                      ?_chosen(offeredPregnancyTestKeys),
                    ].join(' · '),
                    open: _open.contains(EntryFold.bodySignals),
                    onToggle: () => _flip(EntryFold.bodySignals),
                    child: _BodySignals(
                      temperature: _temperature,
                      invalid: _temperatureInvalid,
                      selectedKeys: _symptomKeys,
                      onToggle: (key, selected) {
                        _toggle(key, selected: selected);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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

  void _flip(EntryFold fold) => setState(
    () => _open.contains(fold) ? _open.remove(fold) : _open.add(fold),
  );

  /// The names of whatever is chosen among [keys], or null for nothing.
  String? _chosen(List<String> keys) {
    final l10n = AppLocalizations.of(context);
    final names = [
      for (final key in keys)
        if (_symptomKeys.contains(key)) ?symptomLabel(l10n, key),
    ];
    return names.isEmpty ? null : names.join(', ');
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
        // so she is told why it cannot be kept, with its section opened.
        setState(() {
          _temperatureInvalid = true;
          _open.add(EntryFold.bodySignals);
        });
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

/// The week around the day being logged, one tap per day. Swiping sideways,
/// or the arrows, turns to the week before or after and keeps the weekday, as
/// the week strip in iOS Calendar does; the full date above opens a wheel for
/// a day further back. Days still to come are shown but cannot be chosen.
class _DayStrip extends StatefulWidget {
  const _DayStrip({
    required this.date,
    required this.today,
    required this.onSelect,
    required this.onOpenWheel,
  });

  final CycleDate date;
  final CycleDate today;
  final ValueChanged<CycleDate> onSelect;
  final VoidCallback onOpenWheel;

  /// How far back the strip reaches, the same five years the wheel offers.
  static const weeksBack = 5 * 53;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  PageController? _pages;
  late int _firstDay;

  /// The first day of the week holding [day], in the locale's week.
  CycleDate _weekOf(CycleDate day) =>
      day.subtractDays((day.weekday % 7 - _firstDay) % 7);

  /// The page for the week holding [day]; the last page is this week.
  int _pageOf(CycleDate day) =>
      _DayStrip.weeksBack - _weekOf(day).daysUntil(_weekOf(widget.today)) ~/ 7;

  CycleDate _weekAt(int page) =>
      _weekOf(widget.today).subtractDays(7 * (_DayStrip.weeksBack - page));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // CycleDate counts Monday as 1 and Sunday as 7; the locale counts
    // Sunday as 0.
    _firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    _pages ??= PageController(initialPage: _pageOf(widget.date));
  }

  @override
  void didUpdateWidget(_DayStrip old) {
    super.didUpdateWidget(old);
    // Chosen on the wheel or with an arrow: bring its week into view.
    final pages = _pages!;
    final target = _pageOf(widget.date);
    if (!pages.hasClients || pages.page?.round() == target) return;
    if (MediaQuery.of(context).disableAnimations ||
        (target - pages.page!).abs() > 1.5) {
      pages.jumpToPage(target);
    } else {
      pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// The same weekday [weeks] weeks away, never past today.
  CycleDate _shift(int weeks) {
    final day = widget.date.addDays(7 * weeks);
    return day.isAfter(widget.today) ? widget.today : day;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = widget.date;
    final today = widget.today;
    final page = _pageOf(date);

    return Column(
      children: [
        Row(
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: page > 0 ? () => widget.onSelect(_shift(-1)) : null,
              child: Icon(
                CupertinoIcons.chevron_left,
                size: 20,
                semanticLabel: l10n.entryPreviousWeek,
              ),
            ),
            Expanded(
              child: Semantics(
                button: true,
                hint: l10n.changeDay,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: widget.onOpenWheel,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          date == today
                              ? '${l10n.todayTitle}, '
                                    '${DateFormat.MMMMd(locale).format(_toDateTime(date))}'
                              : DateFormat.MMMMEEEEd(locale)
                                    .format(_toDateTime(date)),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: page < _DayStrip.weeksBack
                  ? () => widget.onSelect(_shift(1))
                  : null,
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 20,
                semanticLabel: l10n.entryNextWeek,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Tall enough for the weekday letter and the day's circle, and for
        // both grown with the text size.
        SizedBox(
          height: 44 + 26 * MediaQuery.textScalerOf(context).scale(1),
          child: PageView.builder(
            controller: _pages,
            itemCount: _DayStrip.weeksBack + 1,
            onPageChanged: (index) {
              // Swiped to another week: the same weekday there.
              final weeks = index - _pageOf(date);
              if (weeks != 0) widget.onSelect(_shift(weeks));
            },
            itemBuilder: (context, index) {
              final start = _weekAt(index);
              return Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    if (start.addDays(i) case final day)
                      Expanded(
                        child: _StripDay(
                          day: day,
                          selected: day == date,
                          isToday: day == today,
                          onTap: day.isAfter(today)
                              ? null
                              : () => widget.onSelect(day),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StripDay extends StatelessWidget {
  const _StripDay({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final CycleDate day;
  final bool selected;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final still = MediaQuery.of(context).disableAnimations;
    final future = onTap == null;
    final number = selected
        ? scheme.onPrimary
        : isToday
        ? scheme.primary
        : future
        ? scheme.onSurface.withValues(alpha: 0.3)
        : scheme.onSurface;

    return Semantics(
      button: !future,
      selected: selected,
      label: DateFormat.yMMMMEEEEd(locale).format(_toDateTime(day)),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Text(
              DateFormat.E(locale).format(_toDateTime(day)).characters.first,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.primary : Colors.transparent,
                border: isToday && !selected
                    ? Border.all(color: scheme.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: number,
                  fontWeight: selected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much she bled, as four tiles with one to three drops, and whether a
/// period started: the two things asked most, together in one card.
///
/// Tapping the chosen tile again clears it, back to "not recorded", which is
/// a different fact from None: she looked and there was no bleeding.
class _PeriodSection extends StatelessWidget {
  const _PeriodSection({
    required this.flow,
    required this.onFlowChanged,
    required this.isPeriodStart,
    required this.onPeriodStartChanged,
  });

  final FlowIntensity? flow;
  final ValueChanged<FlowIntensity?> onFlowChanged;
  final bool isPeriodStart;
  final ValueChanged<bool> onPeriodStartChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(l10n.periodHeading),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(l10n.flowHeading, style: theme.textTheme.bodyLarge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.singleChoiceHint,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Row(
                  children: [
                    for (final (index, value) in FlowIntensity.values.indexed)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                          child: _FlowTile(
                            value: value,
                            selected: flow == value,
                            onTap: () =>
                                onFlowChanged(flow == value ? null : value),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: isPeriodStart,
                onChanged: onPeriodStartChanged,
                title: Text(l10n.periodStartedThisDay),
              ),
            ],
          ),
        ),
        GroupFooter(l10n.periodStartExplanation),
      ],
    );
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final FlowIntensity value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final still = MediaQuery.of(context).disableAnimations;
    final colour = selected ? scheme.onPrimary : scheme.primary;
    final drops = switch (value) {
      FlowIntensity.none => 0,
      FlowIntensity.light => 1,
      FlowIntensity.medium => 2,
      FlowIntensity.heavy => 3,
    };

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: flowLabel(l10n, value),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.groupedBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (drops == 0)
                      Icon(CupertinoIcons.drop, size: 20, color: colour)
                    else
                      for (var i = 0; i < drops; i++)
                        Icon(CupertinoIcons.drop_fill, size: 16, color: colour),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                flowLabel(l10n, value),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thing to tap on or off: a rounded tile with its icon, if it has one,
/// filled in the app's colour once chosen.
class EntryOption extends StatelessWidget {
  /// Creates the option.
  const EntryOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });

  /// Its name.
  final String label;

  /// An icon before the name.
  final IconData? icon;

  /// Whether it is chosen.
  final bool selected;

  /// Called on a tap, to choose it or let it go.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final still = MediaQuery.of(context).disableAnimations;
    final colour = selected ? scheme.onPrimary : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.fromLTRB(icon == null ? 14 : 11, 8, 14, 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.groupedBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final icon?) ...[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? scheme.onPrimary : scheme.primary,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Options for [keys], laid out to wrap, with an optional line under them.
class _Options extends StatelessWidget {
  const _Options({
    required this.keys,
    required this.selectedKeys,
    required this.onToggle,
    this.footer,
  });

  final List<String> keys;
  final Set<String> selectedKeys;
  final void Function(String key, bool selected) onToggle;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in keys)
              if (symptomLabel(l10n, key) case final label?)
                EntryOption(
                  label: label,
                  icon: entryIcon(key),
                  selected: selectedKeys.contains(key),
                  onTap: () => onToggle(key, !selectedKeys.contains(key)),
                ),
          ],
        ),
        if (footer case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A heading, and a card of options for symptoms or moods.
class _OptionsSection extends StatelessWidget {
  const _OptionsSection({
    required this.heading,
    required this.keys,
    required this.selectedKeys,
    required this.onToggle,
  });

  final String heading;
  final List<String> keys;
  final Set<String> selectedKeys;
  final void Function(String key, bool selected) onToggle;

  @override
  Widget build(BuildContext context) => _Group(
    heading: heading,
    padding: const EdgeInsets.all(12),
    child: _Options(keys: keys, selectedKeys: selectedKeys, onToggle: onToggle),
  );
}

/// A row that opens to show [child]: its name, what is chosen in it, and a
/// chevron that turns as it opens.
class _Fold extends StatelessWidget {
  const _Fold({
    required this.heading,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String heading;
  final String? summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final still = MediaQuery.of(context).disableAnimations;
    const duration = Duration(milliseconds: 240);
    final shown = summary?.isNotEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
                child: Row(
                  children: [
                    Text(heading, style: theme.textTheme.bodyLarge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        shown ? summary! : l10n.entryNothingChosen,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: shown
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: still ? Duration.zero : duration,
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: still ? Duration.zero : duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Basal temperature and the ovulation and pregnancy tests: recorded only
/// (docs/cycle-logic.md §9), which the line under them says outright.
class _BodySignals extends StatelessWidget {
  const _BodySignals({
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
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  l10n.temperatureLabel,
                  style: theme.textTheme.bodyMedium,
                ),
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
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              l10n.temperatureInvalid,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.ovulationTestLabel,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        _Options(
          keys: offeredOvulationTestKeys,
          selectedKeys: selectedKeys,
          onToggle: onToggle,
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.pregnancyTestLabel,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        _Options(
          keys: offeredPregnancyTestKeys,
          selectedKeys: selectedKeys,
          onToggle: onToggle,
          footer: '${l10n.bodySignalsFooter} ${l10n.singleChoiceHint}',
        ),
      ],
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
