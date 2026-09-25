import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/logic/cycle_report.dart';
import '../../domain/logic/period_length.dart';
import '../../domain/logic/profile.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../log/entry_labels.dart';
import '../profile/profile_labels.dart';
import '../profile/cycle_mode_section.dart' show modeLabel;

/// Draws [report] as an A4 PDF in the language of [l10n].
///
/// What she said in her [profile] gets its own section, headed as her own
/// statement so it is never mistaken for a figure from her entries
/// (docs/cycle-logic.md §10). Left out entirely when she said nothing.
///
/// Plain on purpose: black on white, the built-in Helvetica (it covers German
/// umlauts, so no font file is bundled), and a table a doctor can scan in
/// seconds. That Helvetica has no en dash, so ranges are written in words. [compress] is only turned off by tests, to read the text back.
Future<Uint8List> renderReportPdf(
  CycleReport report, {
  required AppLocalizations l10n,
  required String locale,
  Profile profile = const Profile(),
  bool compress = true,
}) {
  String day(CycleDate date) =>
      DateFormat.yMMMd(locale)
          .format(DateTime(date.year, date.month, date.day));

  const rose = PdfColor.fromInt(0xFF8C4A5E);
  const grey = PdfColor.fromInt(0xFF6B5A61);
  final heading = pw.TextStyle(
    fontSize: 13,
    fontWeight: pw.FontWeight.bold,
    color: rose,
  );
  const small = pw.TextStyle(fontSize: 9, color: grey);

  String periodCell(PeriodLength? period) => switch (period) {
    KnownPeriodLength(:final days) => l10n.lengthInDays(days),
    OngoingPeriodLength() => l10n.reportOngoing,
    _ => l10n.reportNotLogged,
  };

  pw.Widget row(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label)),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  pw.Widget counts(String title, List<ReportCount> items) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 18),
      pw.Text(title, style: heading),
      pw.SizedBox(height: 6),
      if (items.isEmpty)
        pw.Text(l10n.reportNothingLogged, style: small)
      else
        for (final item in items)
          if (symptomLabel(l10n, item.key) case final label?)
            row(label, l10n.reportLoggedOnDays(item.days)),
    ],
  );

  // Pregnancy hides cycle figures (docs/cycle-logic.md §6); say so rather
  // than leave the reader guessing why a row is empty.
  final hidden = report.mode == CycleMode.pregnancy;
  final missing = hidden ? l10n.reportFiguresHidden : l10n.reportNotEnough;
  final cycleFigure = switch (report.usualCycleLength) {
    final usual? => l10n.lengthInDays(usual),
    null => missing,
  };
  final rangeFigure = switch ((report.shortestCycle, report.longestCycle)) {
    (final shortest?, final longest?) => l10n.reportCycleRangeValue(
      shortest,
      longest,
    ),
    _ => missing,
  };

  final doc =
      pw.Document(
        compress: compress,
        title: l10n.reportTitle,
        creator: 'Period.',
      )..addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
          footer: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Divider(color: grey, thickness: 0.5),
              pw.Text(l10n.reportDisclaimer, style: small),
            ],
          ),
          build: (context) => [
            pw.Text(
              l10n.reportTitle,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(l10n.reportRange(day(report.from), day(report.to))),
            pw.Text(l10n.reportMadeOn(day(report.to)), style: small),
            pw.Text(
              l10n.reportSituation(modeLabel(l10n, report.mode)),
              style: small,
            ),
            pw.SizedBox(height: 18),
            pw.Text(l10n.reportSummaryHeading, style: heading),
            pw.SizedBox(height: 6),
            row(l10n.reportUsualCycle, cycleFigure),
            row(l10n.reportCycleRange, rangeFigure),
            row(
              l10n.usualPeriodLengthHeading,
              report.usualPeriodLength == null
                  ? l10n.reportNotEnough
                  : l10n.lengthInDays(report.usualPeriodLength!),
            ),
            if (!profile.isEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(l10n.reportProfileHeading, style: heading),
              pw.SizedBox(height: 6),
              if (ageThisYear(
                    birthYear: profile.birthYear,
                    currentYear: report.to.year,
                  )
                  case final age?)
                row(l10n.reportAge, '$age'),
              if (profile.usualCycleLength case final days?)
                row(l10n.usualCycleLabel, l10n.lengthInDays(days)),
              if (profile.usualPeriodLength case final days?)
                row(l10n.usualPeriodLabel, l10n.lengthInDays(days)),
              if (profile.contraception case final method?)
                row(l10n.contraceptionLabel, methodLabel(l10n, method)),
              if (profile.conditions.isNotEmpty)
                row(
                  l10n.conditionsLabel,
                  [
                    for (final condition in KnownCondition.values)
                      if (profile.conditions.contains(condition))
                        conditionLabel(l10n, condition),
                  ].join(', '),
                ),
            ],
            pw.SizedBox(height: 18),
            pw.Text(l10n.reportCyclesHeading, style: heading),
            pw.SizedBox(height: 6),
            if (report.cycles.isEmpty)
              pw.Text(l10n.reportNothingLogged, style: small)
            else
              pw.TableHelper.fromTextArray(
                border: null,
                headerAlignment: pw.Alignment.centerLeft,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerDecoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: grey)),
                ),
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                ),
                headers: [
                  l10n.reportColumnStart,
                  l10n.reportColumnCycle,
                  l10n.reportColumnPeriod,
                ],
                data: [
                  for (final cycle in report.cycles)
                    [
                      day(cycle.start),
                      switch (cycle.cycleLength) {
                        final length? => l10n.lengthInDays(length),
                        null => l10n.reportOngoing,
                      },
                      periodCell(cycle.period),
                    ],
                ],
              ),
            counts(l10n.symptomsHeading, report.symptoms),
            counts(l10n.moodHeading, report.moods),
          ],
        ),
      );
  return doc.save();
}
