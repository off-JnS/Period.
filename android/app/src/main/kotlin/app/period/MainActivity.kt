package app.period

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity. local_auth_android refuses to
// authenticate against anything that is not a FragmentActivity, and returns an
// error the Dart side cannot tell apart from "she declined". With a plain
// FlutterActivity the app lock in section 9 would refuse every unlock forever,
// on a device that reports itself perfectly capable of authenticating -- which
// is a permanent lockout from health data that has no backup and no recovery
// path. architecture_test.dart pins this.
class MainActivity : FlutterFragmentActivity()
