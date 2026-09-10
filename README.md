# Period.

A menstrual cycle tracking app for iOS and Android, built in Flutter.

**No backend. No network requests. Ever.** Everything is created, stored and
analysed on the device. There is no account, no login, no sync server and no
telemetry. Health data like this can be used against people in some
jurisdictions, so the app is built so that there is nothing to leak.

The promise is meant to be checkable rather than taken on trust:

- The Android release manifest does not declare `android.permission.INTERNET`,
  so a shipped build cannot open a socket even by accident.
- `test/architecture_test.dart` asserts that, and asserts that no runtime
  dependency is an HTTP or socket client.
- No HTTP client, analytics SDK or crash reporter is a dependency. Crash reports
  come from Xcode Organizer and the Play Console, which are OS-level and collect
  nothing on our behalf.

## State

Built, and unreleased. Four screens — Today, Calendar, History, Settings — over
an encrypted database, with cycle statistics and predictions, the three cycle
modes where predictions are off, an encrypted backup, an optional app lock,
screenshot protection, and German and English throughout.

**Nothing has ever run on a phone.** Not on a device, not on an emulator. The
logic is well tested and the platform integration is not tested at all, because
nothing here can test it. `docs/verification.md` says exactly which is which,
and is worth reading before trusting any of the above.

Notifications are the one requirement still unbuilt: the scheduling logic and
its rules exist, the plugin does not.

## Layout

    lib/
      domain/        pure Dart, imports nothing
        models/      CycleDate, Clock
        logic/       statistics, prediction, pattern detection
      data/          drift tables, DAOs, migrations, backup, SystemClock
      presentation/  today, calendar, analysis, settings
      l10n/          ARB files, German and English

Dependencies point inward only: `presentation` and `data` depend on `domain`,
and `domain` depends on nothing at all.

## Dates

A cycle day is a calendar day, not a point in time. `CycleDate` holds a year, a
month and a day, and does its arithmetic on integer day numbers — no `DateTime`,
no `Duration`, no timezone. Adding `Duration(days: 1)` to a local timestamp does
not reliably advance one calendar day across a clock change, and an entry that
silently moves by a day is a bug users do not report; they just conclude the app
is wrong.

`DateTime.now()` appears in exactly one file, `lib/data/system_clock.dart`.

## Working on it

    flutter pub get
    dart run build_runner build   # models and database are generated, not committed
    flutter analyze
    dart test          # domain runs on the plain Dart VM, with no Flutter binding
    flutter test       # the whole suite

Golden files under `test/presentation/goldens/` are the visual review surface:
they are pictures of real screens, so a change to what a person sees shows up as
an image diff. Regenerate them deliberately, never reflexively, with
`flutter test --update-goldens`, and read the diff before accepting it.

## Running it on a device

Requires a Mac with Xcode for iOS, or the Android SDK for Android; neither has
been done yet. CI compiles the iOS app on every change (`flutter build ios
--no-codesign`), which proves it builds but produces nothing installable — that
still needs a Mac and a signing identity.

The database is encrypted at rest, and that is **tested rather than asserted**:
`test/data/open_database_test.dart` writes a file with a key, reopens it without
one, and checks the plaintext is not on disk. Encryption is selected by the
`hooks.user_defines` block in `pubspec.yaml` — see `CLAUDE.md` §6 before
touching it, because getting it wrong fails silently.

Those tests run on Linux. Confirming the same holds on a real iPhone or Android
device is still outstanding — as is everything else that needs a phone.
`docs/verification.md` is the full account of what is proven and what is not.

`CLAUDE.md` holds the rules for this repository and is worth reading before
changing anything — particularly the sections on dates, migrations and the
dependency allowlist.
