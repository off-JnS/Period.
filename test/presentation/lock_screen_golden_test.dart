import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:period/presentation/lock/lock_screen.dart';

import '../support/widgets.dart';

/// Pictures of the lock screen.
///
/// Worth looking at closely: this is the screen most likely to be seen by
/// someone who is not her, so what it does *not* say matters more than what it
/// does. No cycle day, no date, no estimate.
void main() {
  Future<void> expectGolden(
    WidgetTester tester,
    String name, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await pumpApp(
      tester,
      LockScreen(onUnlock: () {}),
      locale: locale,
      brightness: brightness,
      textScale: textScale,
    );
    await expectLater(
      find.byType(LockScreen),
      matchesGoldenFile('goldens/lock_$name.png'),
    );
  }

  testWidgets('locked', (tester) async {
    await expectGolden(tester, 'screen');
  });

  testWidgets('dark', (tester) async {
    await expectGolden(tester, 'dark', brightness: Brightness.dark);
  });

  testWidgets('German', (tester) async {
    await expectGolden(tester, 'german', locale: const Locale('de'));
  });

  testWidgets('at twice the text size', (tester) async {
    await expectGolden(tester, 'large_text', textScale: 2);
  });
}
