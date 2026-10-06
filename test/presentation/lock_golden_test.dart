import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/domain/models/app_preferences.dart';
import 'package:period/presentation/lock/app_lock.dart';
import 'package:period/presentation/preferences_mapping.dart';

import '../support/fake_authenticator.dart';

/// Golden tests for the lock screen. Regenerate deliberately:
///
///     flutter test --update-goldens
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    AppPreferences preferences = const AppPreferences(
      language: LanguageChoice.english,
    ),
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final lock = AppLock(
      authenticator: FakeAuthenticator()..succeeds = false,
      enabled: true,
      save: ({required enabled}) async {},
    );
    addTearDown(lock.dispose);

    await tester.pumpWidget(
      periodMaterialApp(
        preferences: preferences,
        lock: lock,
        home: const Scaffold(body: Center(child: Text('never visible'))),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lock_$name.png'),
    );
  }

  testWidgets('light', (tester) => expectGolden(tester, 'light'));

  testWidgets(
    'dark',
    (tester) => expectGolden(
      tester,
      'dark',
      preferences: const AppPreferences(
        appearance: AppearanceChoice.dark,
        language: LanguageChoice.english,
      ),
    ),
  );

  testWidgets(
    'German',
    (tester) => expectGolden(
      tester,
      'german',
      preferences: const AppPreferences(language: LanguageChoice.german),
    ),
  );
}
