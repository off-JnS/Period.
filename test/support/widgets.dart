import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/l10n/app_localizations.dart';

/// Wraps [child] in the localisations and theme the app provides, so a widget
/// under test sees what it sees in the real app.
Widget appHarness(
  Widget child, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(useMaterial3: true, brightness: brightness),
  home: child,
);

/// Pumps [child] at a fixed surface size so goldens are stable.
///
/// [textScale] exercises the accessibility requirement that text can be enlarged
/// substantially without the layout clipping or overlapping.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size surface = const Size(400, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: appHarness(child, locale: locale, brightness: brightness),
    ),
  );
  await tester.pumpAndSettle();
}
