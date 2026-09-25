import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database/daos/log_dao.dart';
import '../data/database/daos/settings_dao.dart';
import '../domain/models/app_preferences.dart';
import '../domain/models/clock.dart';
import '../l10n/app_localizations.dart';
import 'analysis/analysis_page.dart';
import 'calendar/calendar_page.dart';
import 'lock/app_lock.dart';
import 'reminders/reminder_sync.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'today/today_page.dart';

/// The four top-level screens behind an iOS tab bar.
///
/// The HIG puts top-level navigation in a tab bar at the bottom rather than in
/// buttons on the home screen, and it keeps each destination one tap away from
/// every other.
///
/// Only the selected tab is built. Each tab reads the database when it appears,
/// so a day logged from the calendar is already on Today when the user switches
/// back, with no cross-tab refresh wiring to get wrong. Every figure is derived
/// on read anyway (section 4), so rebuilding costs a query, not correctness.
class HomeShell extends StatefulWidget {
  /// Creates the shell.
  const HomeShell({
    required this.logDao,
    required this.settingsDao,
    required this.clock,
    this.onPreferencesChanged,
    this.appLock,
    this.reminderSync,
    this.onEraseEverything,
    super.key,
  });

  /// Deletes all data, given the localised messages for how it went.
  final Future<void> Function(String done, String failed)? onEraseEverything;

  /// Keeps scheduled reminders current. Null in tests with no notifications.
  final ReminderSync? reminderSync;

  /// The app lock, for its switch in Settings.
  final AppLock? appLock;

  /// Told when the user changes appearance or language, so the app root can
  /// apply it.
  final ValueChanged<AppPreferences>? onPreferencesChanged;

  /// Reads and writes what the user logged.
  final LogDao logDao;

  /// Reads and writes the user's settings.
  final SettingsDao settingsDao;

  /// Supplies today's calendar day.
  final Clock clock;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back in the app: roll the daily reminders forward, and catch a change
    // of time zone since they were last scheduled.
    _lifecycle = AppLifecycleListener(onResume: _syncReminders);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First build, and any change of language: the notification text is
    // localised when it is scheduled.
    _syncReminders();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _syncReminders() {
    final sync = widget.reminderSync;
    if (sync == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    sync.sync(
      text: l10n.reminderNotificationText,
      channelName: l10n.reminderChannelName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: switch (_tab) {
        0 => TodayPage(
          logDao: widget.logDao,
          settingsDao: widget.settingsDao,
          clock: widget.clock,
          onEntriesChanged: _syncReminders,
        ),
        1 => CalendarPage(
          logDao: widget.logDao,
          settingsDao: widget.settingsDao,
          clock: widget.clock,
          onEntriesChanged: _syncReminders,
        ),
        2 => AnalysisPage(
          logDao: widget.logDao,
          settingsDao: widget.settingsDao,
          clock: widget.clock,
        ),
        _ => SettingsPage(
          settingsDao: widget.settingsDao,
          onPreferencesChanged: widget.onPreferencesChanged,
          appLock: widget.appLock,
          reminderSync: widget.reminderSync,
          onScheduleAffected: _syncReminders,
          onEraseEverything: widget.onEraseEverything,
        ),
      },
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _tab,
        activeColor: scheme.primary,
        inactiveColor: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        backgroundColor: scheme.groupedCard.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
        onTap: (index) {
          if (index == _tab) return;
          HapticFeedback.selectionClick();
          setState(() => _tab = index);
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.circle_outlined),
            activeIcon: const Icon(Icons.trip_origin_rounded),
            label: l10n.todayTitle,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.calendar_month_outlined),
            activeIcon: const Icon(Icons.calendar_month_rounded),
            label: l10n.calendarTitle,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.insert_chart_outlined_rounded),
            activeIcon: const Icon(Icons.insert_chart_rounded),
            label: l10n.analysisTitle,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings_rounded),
            label: l10n.settingsTitle,
          ),
        ],
      ),
    );
  }
}
