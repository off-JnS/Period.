import 'package:flutter/material.dart';

import '../../data/database/daos/settings_dao.dart';
import '../../domain/models/app_preferences.dart';
import '../../domain/models/cycle_mode.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
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
    super.key,
  });

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.settingsDao.cycleSettings();
      final preferences = await widget.settingsDao.appPreferences();
      if (!mounted) return;
      setState(() {
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

    return SettingsScreen(
      settings: settings,
      onChanged: _change,
      preferences: _preferences,
      onPreferencesChanged: _changePreferences,
    );
  }
}
