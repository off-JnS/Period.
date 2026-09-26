import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../l10n/app_localizations.dart';
import '../log/entry_labels.dart';
import '../log/temperature.dart';
import '../theme.dart';
import 'calendar_markers.dart';

/// Everything the preview of one day shows.
class DayPreviewData {
  /// Creates the data.
  const DayPreviewData({
    required this.date,
    required this.today,
    this.entry,
    this.isPeriodStart = false,
    this.marker,
    this.cycleDay,
  });

  /// The day.
  final CycleDate date;

  /// Today, so a future day can be told apart and offered no editing.
  final CycleDate today;

  /// What she logged that day, if anything.
  final DayEntry? entry;

  /// Whether she marked the day as a period start.
  final bool isPeriodStart;

  /// The band the calendar draws on the day, if any.
  final CalendarMarker? marker;

  /// Which day of her cycle it was, when there is a cycle to count in.
  final int? cycleDay;

  /// Whether the day can be logged: it has happened.
  bool get editable => !date.isAfter(today);
}

/// A day at a glance: its date, where it sits in her cycle, and everything
/// she logged, with one button to edit it.
///
/// Read-only on purpose. Tapping a day to look at it should never risk
/// changing it; editing is a deliberate second tap.
class DayPreview extends StatelessWidget {
  /// Creates the preview.
  const DayPreview({required this.data, this.onEdit, super.key});

  /// What to show.
  final DayPreviewData data;

  /// Opens the day for editing. Not offered for a day still to come.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = data.date;

    final lines = entryLines(
      l10n,
      data.entry,
      formatTemperature: (centi) => formatTemperature(centi, locale),
    );
    final logged = data.isPeriodStart || lines.isNotEmpty;

    final status = <(CalendarMarker?, IconData?, String)>[
      if (data.cycleDay case final day?)
        (null, CupertinoIcons.arrow_2_circlepath, l10n.cycleDayAccessibility(day)),
      if (data.isPeriodStart)
        (CalendarMarker.period, null, l10n.legendPeriodStart)
      else if (data.marker == CalendarMarker.period)
        (CalendarMarker.period, null, l10n.legendPeriodDay),
      if (data.marker == CalendarMarker.estimated)
        (CalendarMarker.estimated, null, l10n.legendEstimated),
      if (data.marker == CalendarMarker.fertile)
        (CalendarMarker.fertile, null, l10n.fertileWindowHeading),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                DateFormat.MMMMEEEEd(
                  locale,
                ).format(DateTime(date.year, date.month, date.day)),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (marker, icon, label) in status)
                    _StatusChip(marker: marker, icon: icon, label: label),
                ],
              ),
            ],
            // The caveat goes wherever the fertile window is shown (§8).
            if (data.marker == CalendarMarker.fertile) ...[
              const SizedBox(height: 8),
              Text(
                l10n.fertileWindowCaveat,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (data.editable) ...[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.groupedBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: logged
                      ? Column(
                          children: [
                            for (final line in lines)
                              _Line(icon: _iconFor(line.kind), text: line.text),
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l10n.dayPreviewNothingLogged,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onEdit,
                icon: Icon(
                  logged ? CupertinoIcons.pencil : CupertinoIcons.add,
                  size: 20,
                ),
                label: Text(logged ? l10n.edit : l10n.addEntry),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(EntryLineKind kind) => switch (kind) {
    EntryLineKind.flow => CupertinoIcons.drop,
    EntryLineKind.symptoms => CupertinoIcons.bandage,
    EntryLineKind.mood => CupertinoIcons.smiley,
    EntryLineKind.discharge => CupertinoIcons.drop_triangle,
    EntryLineKind.sex => CupertinoIcons.heart,
    EntryLineKind.pill => CupertinoIcons.capsule,
    EntryLineKind.temperature => CupertinoIcons.thermometer,
    EntryLineKind.ovulationTest => CupertinoIcons.lab_flask,
    EntryLineKind.note => CupertinoIcons.text_quote,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, this.marker, this.icon});

  final CalendarMarker? marker;
  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.groupedBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (marker case final kind?)
              MarkerSwatch(kind, size: 14)
            else if (icon case final glyph?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(glyph, size: 16, color: scheme.primary),
              ),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

/// Shows the preview of [data] as a sheet. Completes with true when she
/// chose to edit the day.
Future<bool> showDayPreview(BuildContext context, DayPreviewData data) async {
  final edit = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.groupedCard,
    builder: (context) => DayPreview(
      data: data,
      onEdit: () => Navigator.of(context).pop(true),
    ),
  );
  return edit ?? false;
}
