package app.period

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    // FlutterFragmentActivity, not FlutterActivity. local_auth_android refuses
    // to authenticate against anything that is not a FragmentActivity, and
    // returns an error the Dart side cannot tell apart from "she declined".
    // With a plain FlutterActivity the app lock in section 9 would refuse every
    // unlock forever, on a device that reports itself perfectly capable of
    // authenticating -- a permanent lockout from health data that has no backup
    // and no recovery path.

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Section 9's screenshot protection. Set here, before the first frame,
        // so there is no moment between launch and protection.
        //
        // FLAG_SECURE blanks the app-switcher thumbnail, which is the exposure
        // section 9 names -- the frame the system captures as the app resigns
        // active, before any Dart code could react to it. The lock covers what
        // happens on the way back; nothing but this covers that frame.
        //
        // It also blocks every screenshot and screen recording, app-wide and
        // permanently. That is a real cost, not an incidental one: she cannot
        // capture her own entries to show a clinician, and the encrypted backup
        // becomes the only way anything leaves the app. Section 9 names
        // FLAG_SECURE outright and section 1 ranks leakage among the two worst
        // outcomes, so the cost is accepted deliberately rather than softened
        // with a toggle nobody asked for.
        //
        // Unconditional, not tied to the optional lock: a switcher thumbnail is
        // exactly the exposure someone who never opens settings still has.
        //
        // architecture_test.dart pins both of the above.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}
