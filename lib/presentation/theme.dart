import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The brand colour: a muted rose.
///
/// Desaturated on purpose. The category's usual candy pink is loud on a screen
/// someone opens in public, and this app is used by people who may not want the
/// glance from across a room to say what they are looking at. Rose enough to
/// have a point of view, quiet enough to read every day.
const seedColour = Color(0xFFB5687F);

/// Deep plum, used for text and the ring's own marks.
const _ink = Color(0xFF3E2233);

/// Corner radius of a grouped card, matching iOS inset-grouped lists.
const cardRadius = 12.0;

/// The light theme.
ThemeData lightTheme() => _themeFrom(Brightness.light);

/// The dark theme.
///
/// Not an afterthought: a cycle app gets opened in bed at night more than most,
/// and a white screen at 2am is its own kind of hostile.
ThemeData darkTheme() => _themeFrom(Brightness.dark);

/// The two layers of an iOS grouped screen, taken from the existing palette.
///
/// iOS separates content from the page by brightness alone: a tinted page with
/// white cards in light mode, near-black with lifted cards in dark mode. No
/// borders and no shadows, which is most of what makes a screen read as native.
extension GroupedColours on ColorScheme {
  /// The page behind the cards.
  Color get groupedBackground => brightness == Brightness.light
      ? surfaceContainer
      : surfaceContainerLowest;

  /// A card sitting on [groupedBackground].
  Color get groupedCard => brightness == Brightness.light
      ? surfaceContainerLowest
      : surfaceContainerLow;
}

ThemeData _themeFrom(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: seedColour,
        brightness: brightness,
      ).copyWith(
        // Warm the neutrals towards the brand rather than leaving the generated
        // grey-violet. Only the surface roles are touched; every accent stays
        // whatever the seed produced, so contrast ratios are still Material's.
        surface: isLight ? const Color(0xFFFCF6F7) : const Color(0xFF161113),
        onSurface: isLight ? _ink : const Color(0xFFF2E4EA),
        surfaceContainerLowest: isLight
            ? Colors.white
            : const Color(0xFF110D0F),
        surfaceContainerLow: isLight
            ? const Color(0xFFFFFBFC)
            : const Color(0xFF1F181B),
        surfaceContainer: isLight
            ? const Color(0xFFF7EDF0)
            : const Color(0xFF261E21),
        surfaceContainerHighest: isLight
            ? const Color(0xFFF0E1E6)
            : const Color(0xFF362B30),
        outlineVariant: isLight
            ? const Color(0xFFEBDCE1)
            : const Color(0xFF3F3338),
      );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  // Merged with the type geometry first: ThemeData keeps sizes out of its
  // text theme until Theme.of localises it, so a style read from here for a
  // component theme would otherwise arrive with no font size at all.
  final text = _textTheme(
    Typography.material2021().englishLike.merge(base.textTheme),
    scheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.groupedBackground,
    textTheme: text,
    // iOS has no ink ripple. A press dims the control instead, which the
    // Cupertino widgets do themselves; everything else gets a faint highlight.
    splashFactory: NoSplash.splashFactory,
    highlightColor: scheme.onSurface.withValues(alpha: 0.06),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: scheme.groupedBackground,
      barBackgroundColor: scheme.groupedBackground.withValues(alpha: 0.85),
      // Built from the Material styles so the navigation bars use the same
      // family as the rest of the screen: SF on an iPhone, and the loaded test
      // font in goldens instead of placeholder boxes.
      textTheme: CupertinoTextThemeData(
        primaryColor: scheme.primary,
        textStyle: text.bodyLarge,
        actionTextStyle: text.bodyLarge?.copyWith(color: scheme.primary),
        navTitleTextStyle: text.titleMedium,
        navLargeTitleTextStyle: text.headlineLarge,
        navActionTextStyle: text.bodyLarge?.copyWith(color: scheme.primary),
        tabLabelTextStyle: text.labelSmall?.copyWith(fontSize: 10),
        dateTimePickerTextStyle: text.bodyLarge?.copyWith(fontSize: 21),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: scheme.groupedBackground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleMedium,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.groupedCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      // Capsules with no outline, filled when on: the look of an iOS toggle
      // pill rather than a Material chip.
      shape: const StadiumBorder(side: BorderSide.none),
      side: BorderSide.none,
      showCheckmark: false,
      backgroundColor: scheme.groupedBackground,
      selectedColor: scheme.primary,
      labelStyle: text.bodyMedium,
      secondaryLabelStyle: text.bodyMedium?.copyWith(color: scheme.onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      // A text view inside a grouped card, as in Notes or Health: the card is
      // the field, so the field itself draws nothing.
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Apple's large prominent button: 50pt tall, continuous rounded rect.
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.titleMedium,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: text.bodyLarge),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.bodyLarge,
      minVerticalPadding: 11,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.5,
      space: 0.5,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Apple's text styles, placed on the Material roles.
///
/// Sizes and tracking follow the iOS Dynamic Type defaults at the Large
/// setting: Large Title 34, Title 1 28, Title 2 22, Title 3 20, Headline 17
/// semibold, Body 17, Subheadline 15, Footnote 13, Caption 12. Tracking is
/// Apple's own per-size value, which is why it goes negative at body sizes.
TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
  TextStyle? ios(
    TextStyle? style,
    double size,
    FontWeight weight,
    double tracking, [
    double height = 1.25,
  ]) => style?.copyWith(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking,
    height: height,
  );

  return base
      .copyWith(
        displayLarge: ios(base.displayLarge, 64, FontWeight.w700, -1.2, 1.05),
        displayMedium: ios(base.displayMedium, 48, FontWeight.w700, -0.8, 1.1),
        displaySmall: ios(base.displaySmall, 40, FontWeight.w700, -0.5, 1.1),
        // Large Title.
        headlineLarge: ios(base.headlineLarge, 34, FontWeight.w700, 0.37, 1.2),
        // Title 1.
        headlineMedium: ios(base.headlineMedium, 28, FontWeight.w700, 0.36),
        // Title 2.
        headlineSmall: ios(base.headlineSmall, 22, FontWeight.w700, 0.35),
        // Title 3.
        titleLarge: ios(base.titleLarge, 20, FontWeight.w600, 0.38),
        // Headline.
        titleMedium: ios(base.titleMedium, 17, FontWeight.w600, -0.41),
        // Subheadline, emphasised.
        titleSmall: ios(base.titleSmall, 15, FontWeight.w600, -0.24),
        // Body.
        bodyLarge: ios(base.bodyLarge, 17, FontWeight.w400, -0.41, 1.3),
        // Subheadline.
        bodyMedium: ios(base.bodyMedium, 15, FontWeight.w400, -0.24, 1.3),
        // Footnote.
        bodySmall: ios(base.bodySmall, 13, FontWeight.w400, -0.08, 1.3),
        labelLarge: ios(base.labelLarge, 15, FontWeight.w600, -0.24),
        labelMedium: ios(base.labelMedium, 13, FontWeight.w600, -0.08),
        // Caption 1.
        labelSmall: ios(base.labelSmall, 12, FontWeight.w500, 0),
      )
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
}
