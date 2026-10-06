import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/database/daos/settings_dao.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_page.dart';
import 'profile_screen.dart';

/// Loads the profile and cycle settings, hands them to [ProfileScreen], and
/// saves every change as it is made, as Settings does.
class ProfilePage extends StatefulWidget {
  /// Creates the page.
  const ProfilePage({
    required this.settingsDao,
    required this.clock,
    this.settingsPage,
    this.onScheduleAffected,
    super.key,
  });

  /// Reads and writes the profile and the cycle settings.
  final SettingsDao settingsDao;

  /// Supplies this year, for her age.
  final Clock clock;

  /// Builds Settings, given the title for its back button. Null hides the
  /// gear.
  final Widget Function(String backLabel)? settingsPage;

  /// Told after a change of mode, which decides whether reminders and the
  /// widget have an estimate to show.
  final VoidCallback? onScheduleAffected;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Profile? _profile;
  CycleSettings _settings = const CycleSettings();
  Object? _error;

  int get _year => widget.clock.today().year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.settingsDao.profile(currentYear: _year);
      final settings = await widget.settingsDao.cycleSettings();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _settings = settings;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _changeProfile(Profile next) async {
    final previous = _profile;
    // Shown at once so the control answers the tap, then written.
    setState(() => _profile = next);
    try {
      await widget.settingsDao.saveProfile(next);
      // Contraception reminders follow the method (docs/cycle-logic.md §8).
      if (next.contraception != previous?.contraception) {
        widget.onScheduleAffected?.call();
      }
    } on Object {
      // Put the screen back to what is actually stored rather than leave it
      // showing an answer that was never saved.
      if (!mounted) return;
      setState(() => _profile = previous);
      await _load();
    }
  }

  Future<void> _changeSettings(CycleSettings next) async {
    final previous = _settings;
    setState(() => _settings = next);
    try {
      await widget.settingsDao.saveCycleSettings(next);
      widget.onScheduleAffected?.call();
    } on Object {
      if (!mounted) return;
      setState(() => _settings = previous);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_error != null) {
      return GroupedPage(
        title: l10n.profileTitle,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.couldNotOpenData, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    final profile = _profile;
    if (profile == null) {
      return GroupedPage(
        title: l10n.profileTitle,
        children: const [
          SizedBox(height: 80),
          Center(child: CircularProgressIndicator.adaptive()),
        ],
      );
    }

    final settingsPage = widget.settingsPage;
    return ProfileScreen(
      profile: profile,
      settings: _settings,
      currentYear: _year,
      onProfileChanged: _changeProfile,
      onSettingsChanged: _changeSettings,
      onOpenSettings: settingsPage == null
          ? null
          : () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => settingsPage(l10n.profileTitle),
              ),
            ),
    );
  }
}
