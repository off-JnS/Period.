import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/database/daos/log_dao.dart';
import '../../data/database/daos/settings_dao.dart';
import '../../domain/logic/profile.dart';
import '../../domain/models/clock.dart';
import '../../domain/models/cycle_date.dart';
import '../../domain/models/cycle_mode.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../grouped_controls.dart';
import '../grouped_page.dart';
import '../profile/profile_screen.dart';
import '../theme.dart';

/// Whether this build shows the introduction on every launch, finished or
/// not, so it can be tried again and again:
///
///     flutter run --dart-define=PERIOD_ONBOARDING=true
///
/// Never in a release build, whatever the flag says.
const onboardingAlwaysRequested =
    bool.fromEnvironment('PERIOD_ONBOARDING') && !kReleaseMode;

/// Keys for the introduction's controls, so tests can reach them without
/// matching text.
abstract final class OnboardingKeys {
  /// The main button at the bottom: Get started, Continue, Start tracking.
  static const next = ValueKey('onboarding.next');

  /// Skip, top right.
  static const skip = ValueKey('onboarding.skip');

  /// Back, top left.
  static const back = ValueKey('onboarding.back');

  /// The first-day row on the last page.
  static const lastPeriod = ValueKey('onboarding.lastPeriod');

  /// The date wheel in the first-day popup.
  static const dateWheel = ValueKey('onboarding.dateWheel');
}

/// The first-launch introduction (docs/roadmap.md, feature 13): what the app
/// is and what it promises, the profile questions, and optionally the first
/// day of her last period.
///
/// There is no account and no sign-in, ever (CLAUDE.md §1); this is the whole
/// of "getting started". Everything is optional and every page can be
/// skipped. Profile answers are saved as they are given, as on Profile; the
/// period start only when she finishes, since that is a real entry.
class OnboardingFlow extends StatefulWidget {
  /// Creates the introduction.
  const OnboardingFlow({
    required this.settingsDao,
    required this.logDao,
    required this.clock,
    required this.onFinished,
    super.key,
  });

  /// Stores her answers and that the introduction is done.
  final SettingsDao settingsDao;

  /// Stores the period start, if she gives one.
  final LogDao logDao;

  /// Supplies today, for her age and the latest day she can pick.
  final Clock clock;

  /// Called once it is finished or skipped and recorded as such.
  final VoidCallback onFinished;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const _pageCount = 3;

  final _pages = PageController();
  int _page = 0;

  Profile _profile = const Profile();
  CycleSettings _settings = const CycleSettings();
  CycleDate? _lastPeriod;
  bool _finishing = false;

  late final CycleDate _today = widget.clock.today();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Whatever is already stored, so that seeing it again (the test flag, or
  /// after an interrupted first launch) starts from her answers.
  Future<void> _load() async {
    try {
      final profile = await widget.settingsDao.profile(
        currentYear: _today.year,
      );
      final settings = await widget.settingsDao.cycleSettings();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _settings = settings;
      });
    } on Object {
      // Starts blank: every answer is optional anyway.
    }
  }

  Future<void> _changeProfile(Profile next) async {
    final previous = _profile;
    setState(() => _profile = next);
    try {
      await widget.settingsDao.saveProfile(next);
    } on Object {
      if (mounted) setState(() => _profile = previous);
    }
  }

  Future<void> _changeSettings(CycleSettings next) async {
    final previous = _settings;
    setState(() => _settings = next);
    try {
      await widget.settingsDao.saveCycleSettings(next);
    } on Object {
      if (mounted) setState(() => _settings = previous);
    }
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  void _goTo(int page) {
    setState(() => _page = page);
    if (_reduceMotion) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _next() async {
    if (_page < _pageCount - 1) {
      _goTo(_page + 1);
    } else {
      await _finish(keepPeriodStart: true);
    }
  }

  /// Records the introduction as done and hands over to the app. The period
  /// start is written first: if that fails she stays here and is told,
  /// rather than arriving in an app without the entry she just gave.
  Future<void> _finish({required bool keepPeriodStart}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      final start = _lastPeriod;
      if (keepPeriodStart && start != null) {
        await widget.logDao.addPeriodStart(start);
      }
      await widget.settingsDao.saveOnboardingDone();
    } on Object {
      if (!mounted) return;
      setState(() => _finishing = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.onboardingSaveFailed)),
      );
      return;
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _pageCount - 1;

    return Scaffold(
      backgroundColor: scheme.groupedBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              page: _page,
              pageCount: _pageCount,
              onBack: _page == 0 ? null : () => _goTo(_page - 1),
              onSkip: _finishing ? null : () => _finish(keepPeriodStart: false),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                // Buttons only: a sideways swipe on a page of wheels and
                // rows would too easily turn it by accident.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final (index, page) in [
                    const _WelcomePage(),
                    _AboutPage(
                      profile: _profile,
                      settings: _settings,
                      currentYear: _today.year,
                      onProfileChanged: _changeProfile,
                      onSettingsChanged: _changeSettings,
                    ),
                    _LastPeriodPage(
                      today: _today,
                      date: _lastPeriod,
                      onChanged: (date) => setState(() => _lastPeriod = date),
                    ),
                  ].indexed)
                    _Parallax(controller: _pages, index: index, child: page),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                key: OnboardingKeys.next,
                onPressed: _finishing ? null : _next,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Row(
                    key: ValueKey(_page),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          switch (_page) {
                            0 => l10n.onboardingStart,
                            _ when last => l10n.onboardingFinish,
                            _ => l10n.onboardingContinue,
                          },
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        last
                            ? CupertinoIcons.checkmark_alt
                            : CupertinoIcons.arrow_right,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back, the progress dots and Skip.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.page,
    required this.pageCount,
    required this.onBack,
    required this.onSkip,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 60,
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedOpacity(
                opacity: onBack == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: CupertinoButton(
                  key: OnboardingKeys.back,
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  minimumSize: const Size(44, 44),
                  onPressed: onBack,
                  child: Icon(
                    CupertinoIcons.chevron_back,
                    semanticLabel: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: l10n.onboardingProgress(page + 1, pageCount),
              excludeSemantics: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pageCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i <= page
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      l10n.onboardingProgress(page + 1, pageCount),
                      key: ValueKey(page),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: CupertinoButton(
                key: OnboardingKeys.skip,
                padding: const EdgeInsetsDirectional.only(end: 16),
                minimumSize: const Size(44, 44),
                onPressed: onSkip,
                child: Text(
                  l10n.onboardingSkip,
                  style: TextStyle(color: scheme.primary, fontSize: 17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and lifts [child] into place, [order] beats after the page appears.
/// Still at once under Reduce Motion.
class _Appear extends StatelessWidget {
  const _Appear({required this.order, required this.child});

  final int order;
  final Widget child;

  static const _step = 70;
  static const _length = 420;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final total = order * _step + _length;
    final curve = Interval(
      order * _step / total,
      1,
      curve: Curves.easeOutCubic,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, value, child) {
        final t = curve.transform(value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Fades and slightly shrinks a page as it slides out, and brings the next
/// one in the same way, so a turn reads as moving forward rather than a
/// flat slide.
class _Parallax extends StatelessWidget {
  const _Parallax({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        final distance = (page - index).abs().clamp(0.0, 1.0);
        return Opacity(
          opacity: 1 - distance * 0.7,
          child: Transform.scale(scale: 1 - distance * 0.06, child: child),
        );
      },
    );
  }
}

/// The large tinted circle at the top of each page. It pops in, then sends
/// out two soft rings and settles: enough to draw the eye, then still.
class _Badge extends StatefulWidget {
  const _Badge(this.icon, {this.size = 88});

  final IconData icon;
  final double size;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  late final _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations && !_rings.isAnimating) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _rings.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    final icon = widget.icon;
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.24),
            scheme.primary.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Icon(icon, size: size * 0.5, color: scheme.primary),
    );
    if (MediaQuery.of(context).disableAnimations) {
      return ExcludeSemantics(child: circle);
    }
    // Room around the circle for the rings, so they never shift the layout.
    final outer = size * 1.5;
    return ExcludeSemantics(
      child: SizedBox(
        width: outer,
        height: outer,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final delay in const [0.0, 0.35])
              AnimatedBuilder(
                animation: _rings,
                builder: (context, _) {
                  final t = ((_rings.value - delay) / (1 - delay)).clamp(
                    0.0,
                    1.0,
                  );
                  if (t == 0 || t == 1) return const SizedBox.shrink();
                  final eased = Curves.easeOutCubic.transform(t);
                  return Container(
                    width: size + (outer - size) * eased,
                    height: size + (outer - size) * eased,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.35 * (1 - t)),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: circle,
            ),
          ],
        ),
      ),
    );
  }
}

/// A page's heading and the line under it.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// What the app is, and its three promises.
class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final promises = [
      (
        CupertinoIcons.lock_shield,
        l10n.onboardingPromiseDeviceTitle,
        l10n.onboardingPromiseDeviceBody,
      ),
      (
        CupertinoIcons.person_crop_circle_badge_xmark,
        l10n.onboardingPromiseAccountTitle,
        l10n.onboardingPromiseAccountBody,
      ),
      (
        CupertinoIcons.chart_bar,
        l10n.onboardingPromiseEstimateTitle,
        l10n.onboardingPromiseEstimateBody,
      ),
    ];

    return _PageScroll(
      children: [
        const Center(child: _Badge(CupertinoIcons.drop_fill, size: 96)),
        const SizedBox(height: 8),
        _Appear(
          order: 1,
          child: _Heading(
            title: l10n.onboardingWelcomeTitle,
            body: l10n.onboardingWelcomeBody,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (index, (icon, title, body))
                    in promises.indexed) ...[
                  if (index > 0) const Divider(indent: 72),
                  _Appear(
                    order: index + 2,
                    child: _Promise(icon: icon, title: title, body: body),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: scheme.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The profile questions, the same rows as on Profile.
class _AboutPage extends StatelessWidget {
  const _AboutPage({
    required this.profile,
    required this.settings,
    required this.currentYear,
    required this.onProfileChanged,
    required this.onSettingsChanged,
  });

  final Profile profile;
  final CycleSettings settings;
  final int currentYear;
  final ValueChanged<Profile> onProfileChanged;
  final ValueChanged<CycleSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = offersContraceptionMode(profile, settings);

    return _PageScroll(
      children: [
        const Center(child: _Badge(CupertinoIcons.person_fill, size: 80)),
        const SizedBox(height: 4),
        _Appear(
          order: 1,
          child: _Heading(
            title: l10n.onboardingAboutTitle,
            body: l10n.onboardingAboutBody,
          ),
        ),
        const SizedBox(height: 20),
        _Appear(
          order: 2,
          child: AboutMeCard(
            profile: profile,
            currentYear: currentYear,
            onChanged: onProfileChanged,
            backLabel: l10n.onboardingAboutTitle,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: offer
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ContraceptionOffer(
                    onAccept: () => onSettingsChanged(
                      settings.copyWith(mode: CycleMode.hormonalContraception),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        _Appear(order: 3, child: GroupFooter(l10n.aboutMeFooter)),
      ],
    );
  }
}

/// A line under the first-day row: a reassurance until she picks, then what
/// will happen with the day she picked.
class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.text,
    required this.done,
    super.key,
  });

  final IconData icon;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 20,
              color: done ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: done ? scheme.onSurface : scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first day of her last period, which becomes her first entry.
class _LastPeriodPage extends StatelessWidget {
  const _LastPeriodPage({
    required this.today,
    required this.date,
    required this.onChanged,
  });

  final CycleDate today;
  final CycleDate? date;
  final ValueChanged<CycleDate?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final picked = date;
    final when = picked == null
        ? ''
        : DateFormat.MMMMd(locale)
              .format(DateTime(picked.year, picked.month, picked.day));

    return _PageScroll(
      children: [
        const Center(child: _Badge(CupertinoIcons.calendar, size: 80)),
        const SizedBox(height: 4),
        _Appear(
          order: 1,
          child: _Heading(
            title: l10n.onboardingLastPeriodTitle,
            body: l10n.onboardingLastPeriodBody,
          ),
        ),
        const SizedBox(height: 24),
        _Appear(
          order: 2,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ValueRow(
              key: OnboardingKeys.lastPeriod,
              icon: CupertinoIcons.drop,
              label: l10n.onboardingLastPeriodLabel,
              value: picked == null ? l10n.onboardingLastPeriodChoose : when,
              placeholder: picked == null,
              onTap: () => _pickDate(context),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Appear(
          order: 3,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: _Hint(
              key: ValueKey(picked),
              icon: picked == null
                  ? CupertinoIcons.info_circle
                  : CupertinoIcons.checkmark_circle_fill,
              text: picked == null
                  ? l10n.onboardingLastPeriodUnsure
                  : l10n.onboardingLastPeriodPicked(when),
              done: picked != null,
            ),
          ),
        ),
      ],
    );
  }

  /// A date wheel with Clear and Done, as the profile's number wheels have.
  /// Never past today: a period that has not happened is not an entry.
  Future<void> _pickDate(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    DateTime asDateTime(CycleDate d) => DateTime(d.year, d.month, d.day);
    var current = date ?? today;
    var result = (picked: false, value: date);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Material(
          color: scheme.groupedCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      if (date != null)
                        CupertinoButton(
                          onPressed: () {
                            result = (picked: true, value: null);
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            l10n.clearAnswer,
                            style: TextStyle(
                              color: CupertinoColors.systemRed.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 72),
                      Expanded(
                        child: Text(
                          l10n.onboardingLastPeriodLabel,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () {
                          result = (picked: true, value: current);
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          l10n.doneButton,
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 216,
                  child: CupertinoDatePicker(
                    key: OnboardingKeys.dateWheel,
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: asDateTime(current),
                    // A year back is plenty for "your last period".
                    minimumDate: asDateTime(today.subtractDays(365)),
                    maximumDate: asDateTime(today),
                    onDateTimeChanged: (picked) => current = CycleDate(
                      picked.year,
                      picked.month,
                      picked.day,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result.picked && result.value != date) onChanged(result.value);
  }
}
