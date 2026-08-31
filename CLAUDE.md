# CLAUDE.md — Period.

Project rules for AI coding agents. Read this fully before writing any code.

## 1. What this app is

A menstrual cycle tracking app. Flutter, iOS + Android, single codebase.

**The defining constraint: this app has no backend and makes no network requests, ever.**
All data is created, stored, and analysed on the device. There is no account, no login,
no sync server, no telemetry. This is the product's core promise and its only real
differentiator against Flo and Clue. Any change that weakens it is wrong, even if it
makes something else easier.

Users are trusting this app with health data that in some jurisdictions can be used
against them. Treat data loss and data leakage as the two worst possible outcomes.

## 2. Architecture

    lib/
      domain/          pure Dart. MUST NOT import flutter, drift, or any plugin.
        models/        Cycle, DayEntry, Symptom, CycleDate
        logic/         statistics, prediction, pattern detection
      data/
        database/      drift tables, DAOs, migrations
        backup/        JSON/CSV export and import
      presentation/
        today/ calendar/ analysis/ settings/
      l10n/            ARB files

**Rule:** anything in `domain/` must be runnable by `dart test` with no Flutter binding
and no device. If you find yourself importing `package:flutter` into `domain/`, the logic
is in the wrong layer. Move it, don't add the import.

Dependencies point inward only: `presentation` → `domain`, `data` → `domain`.
`domain` depends on nothing.

## 3. Dates — read this twice

**A cycle day is a calendar day, not a point in time.**

There is a `CycleDate` value type in `domain/models/`. It holds year, month and day.
It has no time component, no timezone, no UTC offset.

- ALL date fields on all models and all database columns use `CycleDate`.
- NEVER store or persist a `DateTime`, a UTC timestamp, or epoch milliseconds for
  anything representing a cycle day, a period start, or a log entry date.
- `DateTime.now()` may appear in exactly one place: a `Clock` abstraction that returns
  today's `CycleDate`. Everything else takes the date as a parameter. This also makes
  the logic testable — tests pass a fixed date instead of mocking time.
- Never do date arithmetic with `Duration`. Adding `Duration(days: 1)` across a DST
  boundary does not reliably advance one calendar day. Use `CycleDate.addDays()`.

Why this matters: if a user flies to another timezone, or the clocks change, naive
timestamp handling silently shifts her entries by a day. She will not report it as a
bug; she will conclude the app is wrong and delete it.

## 4. Never store derived values

Cycle length, average length, predicted next period, current phase, cycle day number,
fertile window — all of these are **computed on read**, every time, from the stored
period start dates.

Do not add a `cycle_length` column. Do not cache a prediction in the database.
Users retroactively correct period start dates constantly; any stored derivative
immediately becomes inconsistent with the source data.

If a computation is slow enough to matter, memoize it in memory for the current
session. Never persist it.

## 5. Database and migrations

drift over SQLite. Migrations are the single most dangerous part of this codebase:
there is no cloud backup, so a broken migration destroys a user's data permanently
with no recovery path.

- Versioned migrations from schema version 1. Every schema change bumps the version.
- **Never edit a migration that has already shipped.** Add a new one.
- Additive changes only. Do not drop columns or tables. Mark fields unused instead.
- Copy the database file to `<db>.backup-v<n>` before running any migration.
- Every migration needs a test that builds a database at the previous schema version,
  populates it with realistic data, migrates, and asserts the data survived intact.
- **Do not write or modify a migration without explicitly flagging it to the human and
  explaining what it does and what could go wrong.** This is the one place where
  "looks correct" is not good enough.

All model fields except the date are nullable. Nobody logs everything every day.
Symptoms are a separate many-to-many table keyed by string, never fixed columns —
adding a symptom must never require a migration.

## 6. Dependencies

Allowed:

`drift`, `sqlite3_flutter_libs`, `sqlcipher_flutter_libs`, `path_provider`,
`flutter_riverpod`, `freezed`, `json_serializable`, `go_router`, `fl_chart`,
`flutter_local_notifications`, `timezone`, `local_auth`, `health`,
`in_app_purchase`, `intl`, `flutter_localizations`, `pdf`, `printing`,
`share_plus`, `file_picker`, `mocktail`, `golden_toolkit`

**Forbidden, without exception:**

Anything Firebase. Crashlytics, Sentry, or any crash reporter with a network SDK.
Any analytics SDK. RevenueCat or any purchase backend. `http`, `dio`, `web_socket_channel`,
or any HTTP client. Any ad SDK. Any package that phones home.

Crash reports come from Xcode Organizer and Google Play Console, which are OS-level
and require no SDK and no data collection declaration.

The Android release manifest must NOT declare `android.permission.INTERNET`.
This makes the promise technically verifiable and makes any accidental network
dependency fail loudly at build time. If a build breaks because something wants
INTERNET, remove the dependency — do not add the permission.

Before adding ANY new package, ask the human first.

## 7. Testing

- Every function in `domain/logic/` has unit tests. No exceptions.
- Tests must cover the awkward cases, not just the happy path:
  no cycles, one cycle, two cycles, highly irregular cycles, a 21-day cycle,
  a 40-day cycle, a three-month gap, a retroactively corrected start date,
  an in-progress cycle, entries logged out of order.
- Backup round-trip test: export → wipe → import → database is byte-identical.
- Golden tests for the calendar and the Today ring.
- Run `dart test` and `flutter analyze` before declaring any task complete.
  Do not report work as done while either fails.

Test data lives in builders (`aCycle()`, `aDayEntry()`), not inline literals.

## 8. UI copy and legal wording

This app must not become a regulated medical device. That line is crossed by
**claims**, not by code.

Never write UI text, store copy, or documentation that:

- describes the app as suitable for contraception or preventing pregnancy
- diagnoses, or suggests the user has, any condition
- recommends treatment, medication, or supplements
- states a prediction as certainty

Instead:

- Predictions are windows, never single dates. "26.–30." not "28th".
- Say "estimated", "based on your entries", "usually".
- The fertile window view always carries a visible note that it is an estimate and
  not suitable for contraception.
- Irregularity hints are phrased as "this might be worth mentioning to a doctor",
  never as a finding.

All user-facing strings go in ARB files from the first commit. German and English.
Never hardcode a display string in a widget.

## 9. Privacy-sensitive UX

- Notification text is neutral ("Reminder") — no cycle content on the lock screen.
- Screenshot protection in the app switcher (Android `FLAG_SECURE`, iOS blur overlay).
- Optional PIN/biometric lock, enforced on cold start and on resume.
- "Delete all data" must actually delete, with confirmation.
- No color-only information in the calendar; every state needs a shape or label too.

## 10. Special cycle modes

The app must support a mode where predictions are disabled and it only logs:
for hormonal contraception (no natural cycle), pregnancy, and perimenopause.
Without this the app shows confidently wrong predictions to a large share of users.
Prediction code must handle "predictions are off" as a first-class state, not a
special case bolted on later.

## 11. How to work in this repo

- One feature per session. Do not build several screens at once.
- Commit after each working slice. Conventional commits (`feat:`, `fix:`, `test:`).
- Never commit with failing tests or analyzer errors.
- When a requirement is ambiguous, ask. Do not invent cycle-science behaviour —
  the medical logic is specified in the project docs, not up to interpretation.
- When you finish a task, state plainly what you did NOT do or test.

## Definition of done

1. `flutter analyze` clean
2. `dart test` green
3. New logic has tests covering the awkward cases listed in section 7
4. No new dependency added without approval
5. No hardcoded user-facing strings
6. No stored derived values, no `DateTime` in `domain/`
