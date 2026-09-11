# What is verified, and what is not

CLAUDE.md section 11 ends every task with "state plainly what you did NOT do or
test". This is that, for the app as a whole rather than for one change, because
the answer has stopped fitting in a commit message.

It exists for one reason above the others: **this project has found three bugs
that were silent for its entire history, and all three were in code the test
suite covered.** A number like "684 tests passing" says less than it appears to. What
follows is meant to say more.

Read it as a map of where to be suspicious, not as a list of defects. Everything
described as unverified is unverified because nothing here can verify it — not
because anyone declined to.

---

## The short version

**Nothing in this app has ever run on a phone.** Not on a device, not on an
emulator, not once. Everything below follows from that.

---

## What is actually proven

**684 tests.** Not one number but three kinds, which fail for different reasons:

| Kind | Count | What it proves |
|---|---|---|
| Domain logic on the plain Dart VM | 207 | The cycle logic is right, *and* that `lib/domain` reaches no Flutter — `dart test` cannot resolve `package:flutter`, so an import there fails this and nothing else |
| Widget and integration tests | the rest of 684 | Screens render every state, the database round-trips, the backup survives export → wipe → import |
| Goldens | 47 images | What a person actually sees, in English and German, light and dark, at 100% and 200% text |

**Structural guards** in `test/architecture_test.dart` read source and
configuration rather than behaviour: `lib/domain` imports nothing outside a tiny
allowlist and mentions no `DateTime`, `Duration` or epoch value; the release
manifest declares no `INTERNET`; no dependency injects an unacknowledged Android
permission; nothing a shipped build reaches is an HTTP or socket client; an
encrypting SQLite is selected; `FLAG_SECURE` is set and the iOS blur is hooked.

**CI runs the test suite twice on purpose** — once under `dart test test/domain`
and once under `flutter test` — because a Flutter import in the domain breaks
the first while the second stays green. That is not hypothetical: it happened,
and the plain-VM step is the only thing that caught it.

**`build-ios`** runs `flutter build ios --no-codesign`. It proves the app
*links* — CocoaPods resolves, the native code in the plugins compiles. It proves
nothing about whether the app works.

---

## What is not proven

### Everything platform-facing is faked

The seams that touch a real phone are all replaced in tests. That was a
deliberate design choice and it is what makes the suite fast and hermetic; it
also means these have never run:

| Seam | What tests use instead | So this is unknown |
|---|---|---|
| `local_auth` (the app lock) | `FakeAppLock` | Whether the prompt appears, and whether it accepts a real fingerprint or face |
| `flutter_secure_storage` (the database key) | `_MockSecureStorage` | Whether the key survives a reboot, an OS upgrade, or a restore to a new phone |
| `share_plus` / `file_picker` (backup) | a fake transfer | Whether the share sheet appears and returns a usable file |
| `path_provider` | temp directories | Whether the real documents directory is where it is assumed to be |
| `flutter_local_notifications` (reminders) | a mocked plugin, and `FakeReminders` | Whether any notification is ever shown — see below |

### Encryption is proven on the host, not on a phone

`open_database_test.dart` writes a database with a key, reopens it without one,
and asserts the plaintext is not on disk. That is a real end-to-end proof — **of
the build the test ran on**. The shipped app links its SQLite through Dart build
hooks on a different platform. `applyKeyAndVerify` refuses to open a database
where `PRAGMA cipher` answers nothing, so a build without encryption fails loudly
rather than silently, and that guard is itself tested. But the *assertion that
the shipped binary is encrypted* rests on the guard firing correctly on a device,
which nobody has watched happen.

Section 6 says this failure has already happened once.

### The migration has never migrated anyone's data

Schema version 2. The v1 → v2 test builds a database at the old schema, fills it
with realistic rows, migrates, and checks each one survived — using drift's
schema verifier against committed JSON dumps. That is the right test and it
passes.

It is still synthetic. No database that a person actually used has ever been
migrated by this code. And until very recently the copy section 5 requires
**was never being made at all** (see below), so had a migration gone wrong there
would have been nothing to restore from.

### Notifications are built and have never once been seen

This is now the largest untested surface in the project, and the newest.

What exists: the scheduling logic, the settings screen, the stored schedule, the
permission request, the skip-if-already-logged rule, and a `Reminders` seam over
`flutter_local_notifications`. What is tested: all of it, against a **mocked
plugin**. `reminders_test.dart` asserts which series are created, when each one
starts and how each repeats — and every one of those assertions is about what
this app *asked for*, never about what happened.

So everything past the seam is unknown, and none of it can be found out here:

- whether a notification appears at all
- whether it survives a reboot — the manifest declares `RECEIVE_BOOT_COMPLETED`
  and the plugin's boot receiver, both checked by **reading the XML**
- whether Doze delays it, and by how much; reminders are scheduled with
  `inexactAllowWhileIdle`, which asks Android to choose the moment
- whether the first firing lands on the right hour after a clock change. This
  one has a known bound rather than being simply unknown: see
  `docs/cycle-logic.md` section 7, which states it as an hour at most, once,
  and never a day
- whether the Android notification channel is created with the right name, and
  whether a locale change reaches it
- whether iOS shows the permission prompt, and what a refusal looks like when it
  comes back

A permission *revoked later* is now handled rather than unverified: settings
asks the system on every resume and says plainly that the reminder cannot
arrive. Android revokes notifications on its own for apps left unused for a few
months, so this is a state real users reach without doing anything. What is
still unverified is whether the system answers that question truthfully on a
device — the check itself is mocked like everything else here.

The one thing that *is* checked by a test rather than by eye is section 9's
neutrality: `settings_page_test.dart` reads the title and body actually handed
to the scheduler and fails if either contains a word that would give her away on
a lock screen.

### Some guards check shape, not behaviour

`FLAG_SECURE`, the iOS blur overlay, and the `FlutterFragmentActivity` the app
lock needs are all checked by **reading the source files**. No test can ask the
operating system what it put in the app switcher. These guards prove the code is
present and the right shape — which is worth having, since two lockout bugs were
caught exactly that way — but they cannot prove the effect.

The scans strip comments first (`codeOnly`), because a guard once passed on the
strength of the comment explaining it.

---

## Calibration: the three bugs that were silent

None was found by the suite. Two came out of a security review and one out of a
design review, and all three had been wrong since they were written.

**Section 5's copy-before-migration had never run.** `open_database` read the
schema version with a plain `sqlite3.open()` and no key. The file is encrypted,
so that threw on every launch; the caller treats a failed read as "do not touch
it" and skipped the backup. Invisible because **every test of that function
stubbed the version read out** — the real one was never exercised.

**"Delete all data" left her data in two places.** It deleted rows. The
`<db>.backup-v<n>` copies still held her entries, and so did the freed pages
inside the live database. Invisible because the tests asked whether the tables
were empty, and they were.

**The app had no dark theme, and six goldens said otherwise.** `main.dart` set
`theme:` and never `darkTheme:`, so on a phone set to dark the app rendered
light. The dark goldens passed the whole time because the test harness built a
dark theme *of its own* — they were pictures of an appearance the app could not
produce. Invisible because a golden proves what a widget renders under the theme
it is handed, and nothing checked that the app hands it the same one.

The fix was not the missing line. Both now come from `lib/presentation/theme.dart`,
so the harness cannot define an appearance the app does not have, and
`theme_test.dart` asserts the wiring by reading back the brightness a screen
inside the real `MaterialApp` actually gets.

The lesson all three carry: **a test that never runs the real thing tells you
nothing, however green it is.** Where this project stubs a seam, treat the code
behind that seam as untested until something drives it — and a golden is a stub
of the theme unless something proves the app supplies it.

---

## What would close the gap

Roughly in order of how much doubt each removes:

1. **Run it on a phone.** One session with a real device closes more of this
   document than any amount of further test-writing. It is the only way to check
   the encrypted database opens, the key survives, the lock prompts, the share
   sheet works, and the app switcher hides the screen.
2. **Migrate a real database.** Take a v1 file from an actual install and run it
   through. The synthetic test is necessary and is not the same thing.
3. **Watch a reminder arrive.** Set one for two minutes away, lock the phone,
   and wait. Then reboot and wait for the next. Nothing short of that
   distinguishes a working reminder from one this app merely asked for.

Until then, the honest summary is: **the logic is well tested, the platform
integration is not tested at all**, and this document is here so nobody has to
infer that from a green badge.
