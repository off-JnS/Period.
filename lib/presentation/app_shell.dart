import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'analysis/analysis_page.dart';
import 'calendar/calendar_page.dart';
import 'settings/settings_page.dart';
import 'today/today_page.dart';

/// The app's top level: the screens, and the bar that switches between them.
///
/// Section 2's four presentation areas, all of them now built.
class AppShell extends StatefulWidget {
  /// Creates the shell.
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // An IndexedStack rather than swapping the child, so the calendar is
      // still on the month the user left it on when she comes back. Paging
      // three months back, glancing at Today and losing her place would make
      // the correction workflow the calendar exists for tedious.
      body: IndexedStack(
        index: _index,
        children: const [
          TodayPage(),
          CalendarPage(),
          AnalysisPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.navToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: l10n.navCalendar,
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: l10n.navAnalysis,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
