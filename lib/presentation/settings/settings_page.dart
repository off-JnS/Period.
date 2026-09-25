import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database/daos/settings_dao.dart';
import '../../domain/models/app_preferences.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/reminder_settings.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import '../lock/app_lock.dart';
import '../reminders/reminder_sync.dart';
import 'settings_screen.dart';

/// Loads the stored settings, hands them to [SettingsScreen], and saves every
/// change as it is made.
///
/// Saved immediately, with no Save button, as iOS Settings does: a switch that
/// looks on but is not yet stored is a state the user cannot see.
class SettingsPage extends StatefulWidget {
  /// Creates the page.
  const SettingsPage({
    required this.settingsDao,
    this.onPreferencesChanged,
    this.appLock,
    this.reminderSync,
    this.onScheduleAffected,
    this.onEraseEverything,
    this.offerWidget = false,
    super.key,
  });

  /// Whether this platform has the home-screen widget to configure.
  final bool offerWidget;

  /// Deletes all data. Null hides the row.
  final Future<void> Function(String done, String failed)? onEraseEverything;

  /// Asks for notification permission. Null hides the reminders group.
  final ReminderSync? reminderSync;

  /// Told after any change that could move a reminder: the reminder settings
  /// themselves, and the mode, which decides whether there is an estimate.
  final VoidCallback? onScheduleAffected;

  /// The app lock. Null hides its switch, as for a device-less test.
  final AppLock? appLock;

  /// Reads and writes the settings.
  final SettingsDao settingsDao;

  /// Told once a changed appearance or language is stored, so the app can
  /// apply it.
  final ValueChanged<AppPreferences>? onPreferencesChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  CycleSettings? _settings;
  AppPreferences _preferences = const AppPreferences();
  Object? _error;

  /// Set when turning the lock on failed for want of a device passcode.
  bool _lockUnavailable = false;

  ReminderSettings _reminders = const ReminderSettings();
  bool _widgetDetailed = false;

  Future<void> _changeWidgetDetailed(bool detailed) async {
    setState(() => _widgetDetailed = detailed);
    await widget.settingsDao.saveWidgetDetailed(detailed: detailed);
    widget.onScheduleAffected?.call();
  }

  /// Asks, confirms the owner if the lock is on, then deletes everything.
  Future<void> _confirmErase() async {
    final erase = widget.onEraseEverything;
    if (erase == null) return;
    final l10n = AppLocalizations.of(context);
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;

    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.eraseAllQuestion),
        content: Text(l10n.eraseAllExplanation),
        actions: isIos
            ? [
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.eraseAllConfirm),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.eraseAllConfirm),
                ),
              ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final lock = widget.appLock;
    if (lock != null && !await lock.confirmOwner(reason: l10n.eraseAllReason)) {
      return;
    }
    unawaited(HapticFeedback.heavyImpact());
    await erase(l10n.eraseAllDone, l10n.eraseAllFailed);
  }

  /// Set when she turned a reminder on but notifications were refused.
  bool _remindersBlocked = false;

  Future<void> _changeReminders(ReminderSettings next) async {
    final sync = widget.reminderSync;
    if (sync == null) return;
    // Permission is asked for the first time a reminder is turned on, with
    // the switch she just touched as the explanation.
    if (next.anyEnabled && !_reminders.anyEnabled) {
      final granted = await sync.requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() => _remindersBlocked = true);
        return;
      }
    }
    final previous = _reminders;
    setState(() {
      _reminders = next;
      _remindersBlocked = false;
    });
    try {
      await widget.settingsDao.saveReminderSettings(next);
      widget.onScheduleAffected?.call();
    } on Object {
      if (!mounted) return;
      setState(() => _reminders = previous);
    }
  }

  Future<void> _changeLock(bool enabled) async {
    final lock = widget.appLock;
    if (lock == null) return;
    final result = await lock.setEnabled(
      enabled: enabled,
      reason: AppLocalizations.of(context).appLockConfirmReason,
    );
    if (!mounted) return;
    setState(() => _lockUnavailable = result == LockChange.unavailable);
    // The widget shows nothing while the lock is on; tell it.
    if (result == LockChange.changed) widget.onScheduleAffected?.call();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.settingsDao.cycleSettings();
      final preferences = await widget.settingsDao.appPreferences();
      final reminders = await widget.settingsDao.reminderSettings();
      final widgetDetailed = await widget.settingsDao.widgetDetailed();
      if (!mounted) return;
      setState(() {
        _widgetDetailed = widgetDetailed;
        _reminders = reminders;
        _error = null;
        _settings = settings;
        _preferences = preferences;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _change(CycleSettings next) async {
    final previous = _settings;
    // Shown at once so the control answers the tap, then written.
    setState(() => _settings = next);
    try {
      await widget.settingsDao.saveCycleSettings(next);
      widget.onScheduleAffected?.call();
    } on Object {
      // Put the screen back to what is actually stored rather than leave it
      // showing a choice that was never saved.
      if (!mounted) return;
      setState(() => _settings = previous);
      await _load();
    }
  }

  Future<void> _changePreferences(AppPreferences next) async {
    final previous = _preferences;
    setState(() => _preferences = next);
    try {
      await widget.settingsDao.saveAppPreferences(next);
      // Applied only once stored, so the app never shows a theme or language
      // that would not survive a restart.
      widget.onPreferencesChanged?.call(next);
    } on Object {
      if (!mounted) return;
      setState(() => _preferences = previous);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_error != null) {
      return GroupedPage(
        title: l10n.settingsTitle,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.couldNotOpenData, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    final settings = _settings;
    if (settings == null) {
      return GroupedPage(
        title: l10n.settingsTitle,
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator.adaptive()),
        ],
      );
    }

    final lock = widget.appLock;
    Widget screen() => SettingsScreen(
      settings: settings,
      onChanged: _change,
      preferences: _preferences,
      onPreferencesChanged: _changePreferences,
      lockEnabled: lock?.enabled,
      // Held still while the system prompt is up.
      onLockChanged: lock == null || lock.authenticating ? null : _changeLock,
      lockUnavailable: _lockUnavailable,
      reminders: widget.reminderSync == null ? null : _reminders,
      onRemindersChanged: _changeReminders,
      remindersBlocked: _remindersBlocked,
      widgetDetailed: widget.offerWidget ? _widgetDetailed : null,
      onWidgetDetailedChanged: _changeWidgetDetailed,
      onEraseEverything: widget.onEraseEverything == null
          ? null
          : _confirmErase,
    );

    return lock == null
        ? screen()
        : ListenableBuilder(listenable: lock, builder: (_, _) => screen());
  }
}
