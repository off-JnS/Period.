import '../../domain/models/cycle_date.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/symptom.dart';

/// Everything a backup carries.
///
/// Serialised by hand rather than by a generator on the domain models, and
/// deliberately. A backup format is a promise to every file already written: it
/// has to stay readable when the models change. A `toJson` living on [DayEntry]
/// would let an ordinary model refactor silently change the format of every
/// future backup, and nothing would fail until someone tried to restore.
///
/// Dates are ISO strings, per [CycleDate.toIso8601]. Enums are stored by name,
/// like everywhere else in this codebase, so reordering one cannot reinterpret
/// an old file.
class BackupDocument {
  /// Creates a document.
  const BackupDocument({
    required this.exportedOn,
    this.periodStarts = const [],
    this.entries = const [],
    this.settings = const {},
  });

  /// Reads a document, throwing [BackupException] on anything unexpected.
  factory BackupDocument.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int) throw const BackupException(BackupProblem.damaged);
    // Refuse rather than guess. A newer file may hold a cycle mode or a field
    // this build has never heard of, and a partial restore of health data is
    // worse than none.
    if (version > currentFormatVersion) {
      throw const BackupException(BackupProblem.newerFormat);
    }

    try {
      return BackupDocument(
        exportedOn: CycleDate.parseIso8601(json['exportedOn']! as String),
        periodStarts: [
          for (final date in json['periodStarts']! as List<Object?>)
            CycleDate.parseIso8601(date! as String),
        ],
        entries: [
          for (final entry in json['entries']! as List<Object?>)
            _entryFromJson(entry! as Map<String, Object?>),
        ],
        settings: {
          for (final pair
              in (json['settings']! as Map<String, Object?>).entries)
            pair.key: pair.value! as String,
        },
      );
    } on BackupException {
      rethrow;
    } on Object {
      // Type errors, missing keys, an unparseable date: all the same thing to
      // the person holding the file.
      throw const BackupException(BackupProblem.damaged);
    }
  }

  /// The version of this format. Bump it only for a change an older build
  /// could not read correctly, and never edit what a shipped version means.
  static const currentFormatVersion = 1;

  /// The day the backup was made.
  ///
  /// A calendar day, not a timestamp: section 3 keeps clock times out of cycle
  /// data, and the hour someone made a backup is not information they offered.
  final CycleDate exportedOn;

  /// Every period start recorded, oldest first.
  final List<CycleDate> periodStarts;

  /// Every logged day.
  final List<DayEntry> entries;

  /// The settings rows, raw.
  ///
  /// Keys and values exactly as stored, not the typed [StoredSettings]. A
  /// setting added in a later version then round-trips through this format with
  /// no change here at all.
  final Map<String, String> settings;

  /// This document as JSON.
  Map<String, Object?> toJson() => {
    'formatVersion': currentFormatVersion,
    'exportedOn': exportedOn.toIso8601(),
    'periodStarts': [for (final date in periodStarts) date.toIso8601()],
    'entries': [
      for (final entry in entries)
        {
          'date': entry.date.toIso8601(),
          // Absent rather than null: section 5's "not recorded" is the absence
          // of the field, and a smaller file is a smaller thing to leak.
          if (entry.flow != null) 'flow': entry.flow!.name,
          if (entry.note != null) 'note': entry.note,
          if (entry.symptoms.isNotEmpty)
            'symptoms': [for (final symptom in entry.symptoms) symptom.key],
        },
    ],
    'settings': settings,
  };
}

DayEntry _entryFromJson(Map<String, Object?> json) {
  final flow = json['flow'] as String?;
  return DayEntry(
    date: CycleDate.parseIso8601(json['date']! as String),
    flow: flow == null ? null : _flowNamed(flow),
    note: json['note'] as String?,
    symptoms: {
      for (final key in (json['symptoms'] as List<Object?>?) ?? const [])
        Symptom(key: key! as String),
    },
  );
}

/// An unknown flow name means a file this build cannot read faithfully.
///
/// Not silently dropped: the value was something the user recorded, and quietly
/// losing it during a restore is the failure this whole feature exists to
/// prevent.
FlowIntensity _flowNamed(String name) {
  for (final flow in FlowIntensity.values) {
    if (flow.name == name) return flow;
  }
  throw const BackupException(BackupProblem.newerFormat);
}

/// Why a backup could not be read.
enum BackupProblem {
  /// The file could not be decrypted at all.
  ///
  /// A wrong passphrase and a file that was never a backup are the same thing
  /// to SQLite -- both come back as "not a database" -- so this says both
  /// rather than guessing at one.
  couldNotOpen,

  /// Decrypted, but there is no backup inside it.
  notABackup,

  /// Written by a newer version of the app than this one.
  newerFormat,

  /// Readable, but the contents do not make sense.
  damaged,
}

/// Thrown when a backup cannot be read. Carries [problem] so the UI can say
/// which of the four it was rather than "import failed".
class BackupException implements Exception {
  /// Creates the exception.
  const BackupException(this.problem);

  /// What went wrong.
  final BackupProblem problem;

  @override
  String toString() => 'BackupException(${problem.name})';
}
