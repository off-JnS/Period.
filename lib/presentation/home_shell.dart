import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/database/daos/log_dao.dart';
import '../data/database/daos/settings_dao.dart';
import '../domain/models/app_preferences.dart';
import '../domain/models/clock.dart';
import '../l10n/app_localizations.dart';
import 'analysis/analysis_page.dart';
import 'calendar/calendar_page.dart';
import 'lock/app_lock.dart';
import 'profile/profile_page.dart';
import 'reminders/reminder_sync.dart';
import 'widget/widget_sync.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'today/today_page.dart';

/// Keys for the dock's buttons, so tests can reach them without matching
/// text (the dock shows none).
abstract final class HomeShellKeys {
  /// The dock button for each screen, left to right.
  static const dock = [
    ValueKey('dock.today'),
    ValueKey('dock.calendar'),
    ValueKey('dock.analysis'),
    ValueKey('dock.profile'),
  ];
}

/// The four top-level screens, swiped between sideways and reached from a
/// floating dock at the bottom.
///
/// Settings is not a screen of its own here: it opens from the gear on
/// Profile, inside that screen's own navigator, so the dock stays in place.
///
/// Only the screen on show (and one being swiped in) is built. Each reads the
/// database when it appears, so a day logged from the calendar is already on
/// Today when the user comes back, with no cross-screen refresh wiring to get
/// wrong. Every figure is derived on read anyway (section 4), so rebuilding
/// costs a query, not correctness.
class HomeShell extends StatefulWidget {
  /// Creates the shell.
  const HomeShell({
    required this.logDao,
    required this.settingsDao,
    required this.clock,
    this.onPreferencesChanged,
    this.appLock,
    this.reminderSync,
    this.widgetSync,
    this.onEraseEverything,
    super.key,
  });

  /// Deletes all data, given the localised messages for how it went.
  final Future<void> Function(String done, String failed)? onEraseEverything;

  /// Keeps scheduled reminders current. Null in tests with no notifications.
  final ReminderSync? reminderSync;

  /// Keeps the home-screen widget current. Null in tests.
  final WidgetSync? widgetSync;

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
  final _pages = PageController();

  /// Set while a tap on the dock carries the pages over, so the screens
  /// passed on the way do not light up in the dock one after another.
  bool _jumping = false;
  late final AppLifecycleListener _lifecycle;

  /// Lets the navigation bars on Profile and Settings animate into each
  /// other, which a nested navigator only does with its own controller.
  final _profileHeroes = HeroController();

  @override
  void initState() {
    super.initState();
    // Back in the app: roll the daily reminders forward, and catch a change
    // of time zone since they were last scheduled.
    _lifecycle = AppLifecycleListener(onResume: _syncOutsideTheApp);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First build, and any change of language: the notification text is
    // localised when it is scheduled.
    _syncOutsideTheApp();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _profileHeroes.dispose();
    _pages.dispose();
    super.dispose();
  }

  /// Everything that lives outside the app and depends on what is stored:
  /// scheduled reminders and the home-screen widget. Both are rebuilt from
  /// scratch whenever anything they depend on might have changed.
  void _syncOutsideTheApp() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    widget.reminderSync?.sync(
      text: l10n.reminderNotificationText,
      channelName: l10n.reminderChannelName,
    );
    widget.widgetSync?.sync(
      l10n,
      Localizations.localeOf(context).toLanguageTag(),
    );
  }

  Future<void> _select(int index) async {
    if (index == _tab) return;
    setState(() => _tab = index);
    if (MediaQuery.of(context).disableAnimations ||
        (index - (_pages.page ?? _tab)).abs() > 1.5) {
      // A long way over would sweep through every screen in between.
      _pages.jumpToPage(index);
      return;
    }
    _jumping = true;
    await _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
    _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // The screens run on under the dock, which blurs what passes behind
      // it; each screen already pads its end by the bottom inset.
      extendBody: true,
      body: PageView.builder(
        controller: _pages,
        itemCount: 4,
        onPageChanged: (index) {
          if (!_jumping && index != _tab) setState(() => _tab = index);
        },
        itemBuilder: (context, index) => _screen(index),
      ),
      bottomNavigationBar: _Dock(
        selected: _tab,
        onSelect: _select,
        items: [
          (
            icon: Icons.circle_outlined,
            activeIcon: Icons.trip_origin_rounded,
            label: l10n.todayTitle,
          ),
          (
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month_rounded,
            label: l10n.calendarTitle,
          ),
          (
            icon: Icons.insert_chart_outlined_rounded,
            activeIcon: Icons.insert_chart_rounded,
            label: l10n.analysisTitle,
          ),
          (
            icon: CupertinoIcons.person_crop_circle,
            activeIcon: CupertinoIcons.person_crop_circle_fill,
            label: l10n.profileTitle,
          ),
        ],
      ),
    );
  }

  Widget _screen(int index) => switch (index) {
    0 => TodayPage(
      logDao: widget.logDao,
      settingsDao: widget.settingsDao,
      clock: widget.clock,
      onEntriesChanged: _syncOutsideTheApp,
    ),
    1 => CalendarPage(
      logDao: widget.logDao,
      settingsDao: widget.settingsDao,
      clock: widget.clock,
      onEntriesChanged: _syncOutsideTheApp,
    ),
    2 => AnalysisPage(
      logDao: widget.logDao,
      settingsDao: widget.settingsDao,
      clock: widget.clock,
    ),
    _ => Navigator(
      observers: [_profileHeroes],
      onGenerateRoute: (_) => CupertinoPageRoute<void>(
        builder: (_) => ProfilePage(
          settingsDao: widget.settingsDao,
          clock: widget.clock,
          onScheduleAffected: _syncOutsideTheApp,
          settingsPage: (backLabel) => SettingsPage(
            settingsDao: widget.settingsDao,
            onPreferencesChanged: widget.onPreferencesChanged,
            appLock: widget.appLock,
            reminderSync: widget.reminderSync,
            onScheduleAffected: _syncOutsideTheApp,
            onEraseEverything: widget.onEraseEverything,
            offerWidget: widget.widgetSync != null,
            backLabel: backLabel,
          ),
        ),
      ),
    ),
  };
}

/// One button in the dock.
typedef _DockItem = ({IconData icon, IconData activeIcon, String label});

/// A floating, frosted bar of icons, as the dock on the iOS home screen:
/// no words under them and a soft light behind the one on show. Each still
/// has its name for VoiceOver.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.selected,
    required this.onSelect,
    required this.items,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final List<_DockItem> items;

  static const _itemWidth = 78.0;
  static const _height = 54.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light;
    final still = MediaQuery.of(context).disableAnimations;
    const duration = Duration(milliseconds: 320);
    final radius = BorderRadius.circular(24);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Center(
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.08 : 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.groupedCard.withValues(
                      alpha: light ? 0.72 : 0.62,
                    ),
                    borderRadius: radius,
                    border: Border.all(
                      color: (light ? Colors.white : Colors.white24).withValues(
                        alpha: light ? 0.6 : 0.12,
                      ),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: SizedBox(
                      width: _itemWidth * items.length,
                      height: _height - 10,
                      child: Stack(
                        children: [
                          // The light behind the screen on show, sliding
                          // from one icon to the next.
                          AnimatedPositioned(
                            duration: still ? Duration.zero : duration,
                            curve: Curves.easeOutCubic,
                            left: _itemWidth * selected,
                            top: 0,
                            bottom: 0,
                            width: _itemWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (final (index, item) in items.indexed)
                                _DockButton(
                                  key: HomeShellKeys.dock[index],
                                  item: item,
                                  selected: index == selected,
                                  width: _itemWidth,
                                  onTap: () => onSelect(index),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.width,
    required this.onTap,
    super.key,
  });

  final _DockItem item;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.of(context).disableAnimations;
    const duration = Duration(milliseconds: 240);
    final colour = selected
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.85);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: still ? Duration.zero : duration,
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : duration,
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey(selected),
                  size: 26,
                  color: colour,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
