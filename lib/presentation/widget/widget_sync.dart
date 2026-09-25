import 'dart:convert';

import 'package:intl/intl.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../data/widget/widget_bridge.dart';
import '../../domain/logic/cycle_analysis.dart';
import '../../domain/logic/cycle_statistics.dart';
import '../../domain/logic/period_prediction.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/cycle_date.dart';
import '../../l10n/app_localizations.dart';

/// Keeps the home-screen widget's snapshot in step with what is stored.
///
/// The snapshot is the least the widget needs: the last period start (it
/// counts the day itself, so it stays right after midnight without the app),
/// the labels in the app's language, and -- only when she chose the detailed
/// widget -- the estimate as text. When the app lock is on it says only that,
/// and the widget shows an empty ring.
class WidgetSync {
  /// Creates the sync.
  WidgetSync({
    required this.logDao,
    required this.settingsDao,
    required this.bridge,
    required this.clock,
    required this.lockEnabled,
  });

  /// Reads the period starts.
  final LogDao logDao;

  /// Reads the mode and the widget setting.
  final SettingsDao settingsDao;

  /// Where the snapshot goes.
  final WidgetBridge bridge;

  /// Supplies today.
  final Clock clock;

  /// Whether the app lock is on right now.
  final bool Function() lockEnabled;

  Future<void> _last = Future.value();

  /// Rebuilds the snapshot. Queued like reminders, and never throws.
  Future<void> sync(AppLocalizations l10n, String locale) =>
      _last = _last.then((_) => _sync(l10n, locale).catchError((_) {}));

  Future<void> _sync(AppLocalizations l10n, String locale) async {
    await bridge.update(
      jsonEncode(await buildSnapshot(l10n: l10n, locale: locale)),
    );
  }

  /// The snapshot as a JSON-ready map. Public for tests.
  Future<Map<String, Object?>> buildSnapshot({
    required AppLocalizations l10n,
    required String locale,
  }) async {
    final today = clock.today();
    final locked = lockEnabled();
    final settings = await settingsDao.cycleSettings();
    final detailed = await settingsDao.widgetDetailed();
    final labels = {
      'dayLabel': l10n.widgetDay('{day}'),
      'pregnancyLabel': l10n.widgetPregnancy('{weeks}', '{days}'),
    };

    // Locked: nothing of hers leaves the app, not even the start date.
    if (locked) {
      return {
        'locked': true,
        'detailed': false,
        'mode': 'natural',
        'lastStart': null,
        'typicalLength': null,
        'detailLine': null,
        ...labels,
      };
    }

    final starts = [
      for (final start in await logDao.allPeriodStarts())
        if (!start.isAfter(today)) start,
    ];
    final eligible = eligibleForStatistics(cyclesFrom(starts));

    String? detailLine;
    if (detailed) {
      final prediction = predictNextPeriod(
        periodStarts: starts,
        settings: settings,
      );
      if (prediction case PredictedPeriod(:final earliest, :final latest)) {
        String day(CycleDate date) =>
            DateFormat.MMMd(locale)
                .format(DateTime(date.year, date.month, date.day));
        detailLine = l10n.widgetNextPeriod(
          l10n.estimatedRange(day(earliest), day(latest)),
        );
      }
    }

    return {
      'locked': false,
      'detailed': detailed,
      'mode': settings.mode.name,
      'lastStart': starts.isEmpty ? null : starts.last.toIso8601(),
      'typicalLength': settings.cycleStatisticsVisible
          ? medianCycleLength(eligible)?.round()
          : null,
      'detailLine': detailLine,
      ...labels,
    };
  }
}
