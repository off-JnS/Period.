import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/presentation/lock/app_lock.dart';
import 'package:period/presentation/preferences_mapping.dart';

import '../support/fake_authenticator.dart';

/// Through `periodMaterialApp`, the same entry point the app runs, so the
/// gate is checked where it really sits: above the navigator.
void main() {
  late FakeAuthenticator auth;

  setUp(() => auth = FakeAuthenticator());

  // The lifecycle state lives on the shared test binding; put it back so one
  // test's "hidden" cannot leak into the next.
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  AppLock lockWith({bool enabled = true}) => AppLock(
    authenticator: auth,
    enabled: enabled,
    save: ({required enabled}) async {},
  );

  Future<AppLock> pumpApp(
    WidgetTester tester, {
    bool enabled = true,
    Locale locale = const Locale('en'),
  }) async {
    final lock = lockWith(enabled: enabled);
    addTearDown(lock.dispose);
    await tester.pumpWidget(
      periodMaterialApp(
        preferences: AppPreferences(
          language: locale.languageCode == 'de'
              ? LanguageChoice.german
              : LanguageChoice.english,
        ),
        lock: lock,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('a sheet')),
                ),
                child: const Text('her data'),
              ),
            ),
          ),
        ),
      ),
    );
    return lock;
  }

  void setLifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  testWidgets('a cold start with the lock on asks at once', (tester) async {
    auth.succeeds = false;
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(auth.prompts, 1);
    expect(find.text('Period. is locked'), findsOneWidget);
  });

  testWidgets('while locked, her data is hidden from touch and VoiceOver', (
    tester,
  ) async {
    auth.succeeds = false;
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('her data'), findsNothing);
    await tester.tap(find.text('her data'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('a sheet'), findsNothing);
  });

  testWidgets('a confirmed owner gets straight in', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('Period. is locked'), findsNothing);
    expect(find.semantics.byLabel('her data'), findsOne);
  });

  testWidgets('after a cancelled prompt, Unlock asks again', (tester) async {
    auth.succeeds = false;
    await pumpApp(tester);
    await tester.pumpAndSettle();

    auth.succeeds = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(auth.prompts, 2);
    expect(find.text('Period. is locked'), findsNothing);
  });

  testWidgets('leaving the app locks it, and coming back asks', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(auth.prompts, 1);

    auth.succeeds = false;
    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.hidden);

    // Flutter draws no frames while hidden; on a device the native blur
    // covers that gap. The first frame back is already the lock screen.
    setLifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Period. is locked'), findsOneWidget);
    expect(find.semantics.byLabel('her data'), findsNothing);

    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(auth.prompts, 2);
  });

  testWidgets('Control Center or the Face ID prompt does not lock it', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    // Losing focus without leaving the screen.
    setLifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Period. is locked'), findsNothing);
    expect(auth.prompts, 1);
  });

  testWidgets('the cover lies over open dialogs and sheets too', (
    tester,
  ) async {
    final lock = await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('her data'));
    await tester.pumpAndSettle();
    expect(find.text('a sheet'), findsOneWidget);

    lock.appHidden();
    await tester.pump();
    expect(find.semantics.byLabel('a sheet'), findsNothing);
    expect(find.text('Period. is locked'), findsOneWidget);
  });

  testWidgets('with the lock off, nothing is ever covered', (tester) async {
    await pumpApp(tester, enabled: false);
    await tester.pumpAndSettle();
    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.hidden);
    setLifecycle(tester, AppLifecycleState.inactive);
    setLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Period. is locked'), findsNothing);
    expect(auth.prompts, 0);
  });

  testWidgets('the lock screen speaks German', (tester) async {
    auth.succeeds = false;
    await pumpApp(tester, locale: const Locale('de'));
    await tester.pumpAndSettle();
    expect(find.text('Period. ist gesperrt'), findsOneWidget);
    expect(find.text('Entsperren'), findsOneWidget);
  });
}
