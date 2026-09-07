import 'package:flutter/material.dart';

import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/symptom.dart';
import '../../l10n/app_localizations.dart';

/// The symptoms offered in the UI.
///
/// Keys only. The database stores the key and section 8 translates it for
/// display, so a German user sees German rather than an English label frozen
/// into her data. Section 5 keys symptoms by string precisely so this list can
/// grow without a migration — adding one here is the whole change.
const offeredSymptomKeys = <String>[
  'cramps',
  'headache',
  'tiredness',
  'bloating',
  'mood_change',
  'back_pain',
];

/// What the user chose in the logging sheet.
class LoggedDay {
  /// Creates the result.
  const LoggedDay({required this.entry, required this.isPeriodStart});

  /// The day's entry as edited.
  final DayEntry entry;

  /// Whether the user marked this day as the first day of a period.
  ///
  /// Separate from the entry because it is a different fact stored in a
  /// different table: section 4 treats period starts as the source of truth for
  /// cycle boundaries, while an entry is just what was observed.
  final bool isPeriodStart;
}

/// Records what happened on one day.
///
/// Returns the edited day, or null if the user cancelled. Nothing is written
/// here; the caller saves, so this widget stays testable without a database.
class LogEntrySheet extends StatefulWidget {
  /// Creates the sheet.
  const LogEntrySheet({
    required this.date,
    this.existing,
    this.isPeriodStart = false,
    super.key,
  });

  /// The day being recorded.
  final CycleDate date;

  /// What was already logged, if anything.
  final DayEntry? existing;

  /// Whether this day is already marked as a period start.
  final bool isPeriodStart;

  @override
  State<LogEntrySheet> createState() => _LogEntrySheetState();
}

class _LogEntrySheetState extends State<LogEntrySheet> {
  late FlowIntensity? _flow = widget.existing?.flow;
  late final Set<String> _symptomKeys = {
    for (final symptom in widget.existing?.symptoms ?? const <Symptom>{})
      symptom.key,
  };
  late bool _isPeriodStart = widget.isPeriodStart;
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final note = _note.text.trim();
    Navigator.of(context).pop(
      LoggedDay(
        entry: DayEntry(
          date: widget.date,
          flow: _flow,
          // Empty means not recorded, not an empty note.
          note: note.isEmpty ? null : note,
          symptoms: {for (final key in _symptomKeys) Symptom(key: key)},
        ),
        isPeriodStart: _isPeriodStart,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        // Keeps the sheet above the keyboard when the note field is focused.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.logForDate(_formatDay(context, widget.date)),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // First, because it is the only choice that changes what the app
              // calculates. Everything below is recorded and not interpreted.
              SwitchListTile(
                value: _isPeriodStart,
                onChanged: (value) => setState(() => _isPeriodStart = value),
                title: Text(l10n.periodStartedToday),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),

              _Heading(l10n.flowHeading),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final flow in FlowIntensity.values)
                    ChoiceChip(
                      label: Text(_flowLabel(l10n, flow)),
                      selected: _flow == flow,
                      // Tapping the selected value clears it, so "not recorded"
                      // stays reachable after a mistake. Section 5 keeps null
                      // meaningfully different from FlowIntensity.none.
                      onSelected: (selected) =>
                          setState(() => _flow = selected ? flow : null),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              _Heading(l10n.symptomsHeading),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in offeredSymptomKeys)
                    FilterChip(
                      label: Text(_symptomLabel(l10n, key)),
                      selected: _symptomKeys.contains(key),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _symptomKeys.add(key)
                            : _symptomKeys.remove(key);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              _Heading(l10n.noteHeading),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: l10n.noteHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: Text(l10n.save)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

String _flowLabel(AppLocalizations l10n, FlowIntensity flow) => switch (flow) {
  FlowIntensity.none => l10n.flowNone,
  FlowIntensity.light => l10n.flowLight,
  FlowIntensity.medium => l10n.flowMedium,
  FlowIntensity.heavy => l10n.flowHeavy,
};

/// Translates a stored symptom key for display.
///
/// An unknown key falls back to the key itself rather than crashing: a database
/// restored from a newer version of the app may contain symptoms this build has
/// never heard of, and showing something is better than losing her data.
String _symptomLabel(AppLocalizations l10n, String key) => switch (key) {
  'cramps' => l10n.symptomCramps,
  'headache' => l10n.symptomHeadache,
  'tiredness' => l10n.symptomTiredness,
  'bloating' => l10n.symptomBloating,
  'mood_change' => l10n.symptomMoodChange,
  'back_pain' => l10n.symptomBackPain,
  _ => key,
};

String _formatDay(BuildContext context, CycleDate date) =>
    MaterialLocalizations.of(context)
        .formatMediumDate(DateTime(date.year, date.month, date.day));
