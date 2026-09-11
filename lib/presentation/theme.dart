import 'package:flutter/material.dart';

/// The app's two appearances, defined once.
///
/// Here rather than inline in `main.dart` for a reason the test suite learned
/// the hard way: the widget harness built a theme of its own, so six dark
/// goldens rendered an appearance the app never constructed. Anything that
/// renders this app -- the app itself, a test, a golden -- takes its theme from
/// this file, so a picture of the app is a picture of the app.
///
/// No in-app appearance switch, deliberately. The device setting decides, which
/// is what people expect and what leaves them one place to change it.
ThemeData appTheme({Brightness brightness = Brightness.light}) =>
    ThemeData(useMaterial3: true, brightness: brightness);

/// The light appearance.
ThemeData get appLightTheme => appTheme();

/// The dark appearance.
///
/// Not a nicety. Section 1 treats this data as something that can be used
/// against its owner, and a screen that glares white in a dark room is its own
/// small exposure -- the app should not be the brightest thing in the room when
/// she checks it.
ThemeData get appDarkTheme => appTheme(brightness: Brightness.dark);
