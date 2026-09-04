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

Early. This is the foundation only: the layer structure, the calendar-day type
and the clock. There is no cycle logic, no database and no real UI yet.

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
    flutter analyze
    dart test          # domain runs on the plain Dart VM, with no Flutter binding
    flutter test       # the whole suite

`CLAUDE.md` holds the rules for this repository and is worth reading before
changing anything — particularly the sections on dates, migrations and the
dependency allowlist.
