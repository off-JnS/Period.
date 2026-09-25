import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:period/data/database/database.dart';
import 'package:period/domain/logic/cycle_report.dart';
import 'package:period/domain/models/cycle_mode.dart';
import 'package:period/domain/models/day_entry.dart';
import 'package:period/domain/models/profile.dart';
import 'package:period/l10n/app_localizations.dart';
import 'package:period/presentation/analysis/analysis_page.dart';
import 'package:period/presentation/report/report_pdf.dart';
import 'package:period/presentation/report/share_report.dart';
import 'package:share_plus/share_plus.dart';

import '../support/database.dart';
import '../support/dates.dart';
import '../support/fixed_clock.dart';
import '../support/models.dart';
import '../support/widgets.dart';

void main() {
  // The app's localisations load these; plain tests have to.
  setUpAll(initializeDateFormatting);

  final today = aDate(2024, 12, 20);
  final starts = regularPeriodStarts(
    from: aDate(2024, 6, 1),
    length: 28,
    count: 7,
  );

  CycleReport sampleReport({CycleMode mode = CycleMode.natural}) =>
      buildCycleReport(
        periodStarts: starts,
        entries: [
          for (final start in starts)
            for (var i = 0; i < 5; i++)
              aDayEntry(
                date: start.addDays(i),
                flow: FlowIntensity.medium,
                symptoms: {if (i == 0) aSymptom(key: 'cramps')},
                note: i == 0 ? 'secret note' : null,
              ),
          aDayEntry(
            date: aDate(2024, 12, 1),
            symptoms: {
              aSymptom(key: 'sex.unprotected'),
              aSymptom(key: 'mood.sad'),
            },
          ),
        ],
        settings: CycleSettings(mode: mode),
        today: today,
      );

  /// The text of an uncompressed PDF, near enough to search.
  Future<String> pdfText(
    CycleReport report,
    String language, {
    Profile profile = const Profile(),
  }) async {
    final l10n = await AppLocalizations.delegate.load(Locale(language));
    final bytes = await renderReportPdf(
      report,
      l10n: l10n,
      locale: language,
      profile: profile,
      compress: false,
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    // Page text is written word by word as `[(word)]TJ`; join the words so a
    // phrase can be searched for.
    final raw = latin1.decode(bytes);
    final runs = RegExp(r'\[\(((?:\\.|[^\\)])*)\)\]TJ')
        .allMatches(raw)
        .map((m) => m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'));
    return runs.join(' ');
  }

  group('the PDF', () {
    test('states the summary, the cycles and the logged symptoms', () async {
      final text = await pdfText(sampleReport(), 'en');
      expect(text, contains('Cycle report'));
      expect(text, contains('Usual cycle length'));
      expect(text, contains('28 days'));
      expect(text, contains('Cramps'));
      expect(text, contains('Sad'));
    });

    test('states her profile answers as her own, when she gave any', () async {
      final text = await pdfText(
        sampleReport(),
        'en',
        profile: const Profile(
          birthYear: 1990,
          usualCycleLength: 31,
          contraception: ContraceptionMethod.copperIud,
          conditions: {KnownCondition.pcos, KnownCondition.pmdd},
        ),
      );
      final stated = text.substring(
        text.indexOf('Stated by me'),
        text.indexOf('Cycles Period started'),
      );
      expect(stated, contains('Age this year 34'));
      expect(stated, contains('Usual cycle length 31 days'));
      expect(stated, contains('Copper IUD'));
      expect(stated, contains('PCOS, PMDD'));
      // Nothing said about period length, so no row for it.
      expect(stated, isNot(contains('Usual period length')));
    });

    test('leaves the profile section out when she said nothing', () async {
      final text = await pdfText(sampleReport(), 'en');
      expect(text, isNot(contains('Stated by me')));
    });

    test('always carries the not-a-diagnosis note (section 8)', () async {
      final text = await pdfText(sampleReport(), 'en');
      expect(text, contains('not a diagnosis'));
    });

    test('never contains notes or sex', () async {
      final text = await pdfText(sampleReport(), 'en');
      expect(text, isNot(contains('secret note')));
      expect(text, isNot(contains('Unprotected')));
    });

    test('says cycle figures are hidden in pregnancy', () async {
      final text = await pdfText(sampleReport(mode: CycleMode.pregnancy), 'en');
      expect(text, contains('Not shown during pregnancy'));
    });

    test('renders German, umlauts included', () async {
      final text = await pdfText(sampleReport(), 'de');
      expect(text, contains('Zyklusbericht'));
      expect(text, contains('Überblick'));
      // Written in words: the PDF's built-in font has no en dash.
      expect(text, contains('bis'));
      expect(text, isNot(contains('–')));
    });
  });

  group('sharing', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('period_share'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('shares a PDF file and deletes it afterwards', () async {
      XFile? shared;
      bool? existedWhileSharing;
      await sharePdf(
        Uint8List.fromList(utf8.encode('%PDF-fake')),
        fileName: 'cycle-report-2024-12-20',
        directory: () async => dir,
        share: (file, origin) async {
          shared = file;
          existedWhileSharing = File(file.path).existsSync();
        },
      );
      expect(shared!.path, endsWith('cycle-report-2024-12-20.pdf'));
      expect(shared!.mimeType, 'application/pdf');
      expect(existedWhileSharing, isTrue);
      expect(dir.listSync(), isEmpty);
    });

    test('deletes the file even when sharing fails', () async {
      await expectLater(
        sharePdf(
          Uint8List(1),
          fileName: 'x',
          directory: () async => dir,
          share: (file, origin) => Future.error(StateError('no sheet')),
        ),
        throwsStateError,
      );
      expect(dir.listSync(), isEmpty);
    });
  });

  group('the cycles screen', () {
    late AppDatabase database;
    late Directory dir;

    setUp(() async {
      database = aDatabase();
      dir = Directory.systemTemp.createTempSync('period_share_page');
      for (final start in starts) {
        await database.logDao.addPeriodStart(start);
      }
    });
    tearDown(() async {
      await database.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('tapping share hands the sheet a real PDF', (tester) async {
      Uint8List? sharedBytes;
      await pumpApp(
        tester,
        AnalysisPage(
          logDao: database.logDao,
          settingsDao: database.settingsDao,
          clock: FixedClock(today),
          temporaryDirectory: () async => dir,
          shareFile: (file, origin) async =>
              sharedBytes = await File(file.path).readAsBytes(),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Share a report for your doctor'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Share a report for your doctor'));
        // Rendering the PDF is real work; let it finish.
        for (var i = 0; i < 50 && sharedBytes == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

      expect(sharedBytes, isNotNull);
      expect(ascii.decode(sharedBytes!.sublist(0, 5)), '%PDF-');
      expect(find.textContaining('what it contains'), findsNothing);
      expect(find.textContaining('never included'), findsOneWidget);
    });
  });
}
