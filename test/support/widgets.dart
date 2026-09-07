import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/data/database/database.dart';
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
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: appHarness(child, locale: locale, brightness: brightness),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Unmount before the test ends. Disposing the provider scope cancels drift's
  // query streams, and that cancellation schedules a zero-duration timer; if
  // the tree is still mounted when the test finishes, flutter_test sees that
  // timer as pending and fails the test for it. Pumping once here lets it fire.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// Pumps [child] for a test backed by a real database.
///
/// [pumpApp] cannot be used for these. It ends in `pumpAndSettle`, which runs
/// inside a fake-async zone where drift's real I/O never completes — so the
/// screen stays on its loading spinner, the spinner animates forever, and
/// settling never finishes. `runAsync` steps outside that zone so the query can
/// actually run, and the pump afterwards rebuilds with the result.
Future<void> pumpWithDatabase(
  WidgetTester tester,
  Widget child, {
  required AppDatabase database,
  required List<Override> overrides,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  Size surface = const Size(400, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: appHarness(child, locale: locale, brightness: brightness),
    ),
  );
  await settleDatabase(tester);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// Lets pending database work finish and rebuilds with the result.
///
/// Call after anything that writes, so the stream has a chance to re-emit
/// before the next expectation reads the screen.
/// Use this INSTEAD OF `pumpAndSettle` anywhere a real database is involved.
///
/// `pumpAndSettle` runs entirely in a fake-async zone, so a callback that
/// awaits a database read never resolves and the settle spins until it times
/// out. Two rules make this work where that does not: the waiting happens
/// inside `runAsync` so real I/O can complete, and the pumping happens outside
/// it, because pumping inside `runAsync` is unsupported and silently fails to
/// advance the frame. Each pump also advances the clock so sheet and button
/// animations finish.
Future<void> settleDatabase(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
