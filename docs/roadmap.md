# Roadmap — Period.

What is left to build, in the order it will be built, and how. One feature per
session (CLAUDE.md §11); each is reviewed by the owner before the next begins.

Measured against Flo, the category leader, but not copied from it. About half of
Flo's features need a server or make medical claims. Those are listed at the end
with the reason they are out, so the question does not have to be reopened.

**Status key:** ✅ done · 🔨 in progress · ⏳ planned · ❓ needs a decision first

**Decided 2026-09-25:** `http` arrives in `pubspec.lock` through `timezone`;
allowed, because `test/network_guard_test.dart` proves the app cannot reach it
(see CLAUDE.md §6).

---

## Already built

| Feature | Where |
|---|---|
| Period starts, flow, symptoms, notes, per day | log sheet |
| Month calendar with shaped markers (§9) | Calendar tab |
| Next-period estimate as a window, never a date (§8) | Today |
| Fertile window, opt-in, caveat always visible | Today, Settings |
| Cycle history: usual length, variation, chart | Your cycles tab |
| Irregularity hint, rare and dismissible | Today |
| Cycle modes: contraception, pregnancy, perimenopause (§10) | Settings |
| Encrypted database, schema v2, pre-migration backup | data layer |
| Light / dark / automatic, German / English / device | Settings |
| App lock (Face ID / Touch ID / passcode), app-switcher blur | Settings |

---

## Planned, in order

Order is by how often the feature is used, then by risk. Anything needing a
schema migration or a change to `docs/cycle-logic.md` says so, because §5 and
§11 require both to be done carefully and flagged.

### 1. Reminders 🔨 — built, awaiting review

**What:** two optional local notifications.
- *Period coming* — a set number of days (1–5) before the first day of the
  estimated window. Only when an estimate exists, so never in a mode with
  predictions off.
- *Daily log* — every day at a chosen time, to prompt logging.

Both at a time she chooses. **Every notification reads only "Reminder"** (§9):
nothing about cycles, periods or dates appears on the lock screen, and the two
kinds are deliberately indistinguishable there.

**How:**
- `flutter_local_notifications` + `timezone` (both allowlisted, §6).
- Domain: a pure function that turns the prediction, the reminder settings and
  today into a list of (day, kind) pairs. Unit-tested. Rule added to
  `docs/cycle-logic.md` first (§11).
- Scheduling as individual one-off notifications for the next 30 days, rebuilt
  on every launch, return to the app, save and settings change. Not the
  plugin's repeating API: that needs the device's IANA time zone name, which no
  allowlisted package supplies, and a daily repeat pinned to UTC would drift by
  an hour at every daylight-saving change. One-off times computed from the
  device's local calendar do not.
- Behind a `ReminderScheduler` interface, like `DeviceAuthenticator`, so tests
  need no platform channel.
- Settings: a Reminders group with two switches, days-before, and a time.
  Permission is requested when she first turns one on, not at launch.
- Stored in the settings table as new keys — **no migration**.
- iOS allows 64 pending notifications; 30 days of daily plus one period
  reminder stays under it.

**Not in this step:** a pill reminder (part of feature 2's contraception
logging), snooze, custom notification text.

### 2. More to log ⏳

**What:** mood, sex (protected / unprotected / none), discharge, and for the
contraception mode, "pill taken".

**How:** mood and discharge as string-keyed rows like symptoms (§5: no fixed
columns) — **no migration**. Sex and pill as their own small keyed sets in the
same table family. Log sheet gains sections; Today's summary lists them.

❓ Wording for "sex" must not drift into contraceptive guidance (§8, §7 of the
spec). To be drafted and reviewed before any code.

### 3. Period length ⏳

**What:** mark the day a period ends; "periods usually last N days" in history.

**How:** an end is a derived fact from logged flow days, or an explicit end
marker — decided in `docs/cycle-logic.md` first (§11), since §4 forbids storing
anything derivable. Descriptive only, so allowed in every mode (spec §6).
Possibly a migration if an explicit marker is chosen; flagged if so.

### 4. Delete all data ⏳

**What:** a red row at the bottom of Settings; an iOS confirmation stating it
cannot be undone; then everything is wiped — entries, starts, settings, the
pre-migration backups, scheduled notifications — and the app returns to a fresh
install state.

**How:** `LogDao.deleteEverything()` already clears every table. Adds removal of
`*.backup-v*` files and cancelling reminders. Required by §9.

### 5. Backup and restore ⏳

**What:** export everything to a file via the share sheet; import it on a new
phone. The only way to move data, since there is no cloud.

**How:** `share_plus`, `file_picker` (allowlisted). JSON, versioned. ❓ Encrypted
with a password she chooses, or plain? Plain is readable by anyone who finds
the file. Round-trip test required by §7: export → wipe → import → identical.

### 6. Doctor report ⏳

**What:** a PDF of recent cycles, lengths, variation, period days and symptoms,
to show a doctor. Flo charges for this.

**How:** `pdf`, `printing` (allowlisted). Wording reviewed against §8: states
what was recorded, never what it means.

### 7. Body signals ⏳ ❓

**What:** basal body temperature and ovulation (LH) test results.

**How:** `docs/cycle-logic.md` §4 names this as the only honest way to narrow
the fertile window. The method (e.g. a temperature shift rule) must be written
into the spec with sources before any code, and the owner must decide whether
it changes the fertile window or is only logged.

### 8. Apple Health / Health Connect ⏳ ❓

**What:** write periods and symptoms to Apple Health (and read them back).

**How:** `health` (allowlisted). ❓ A privacy decision: data written to Apple
Health leaves this app's encryption and can sync through iCloud. Off by default,
with that stated plainly beside the switch, if built at all.

### 9. Pregnancy week counter ⏳

**What:** in pregnancy mode, "week N" instead of a cycle day.

**How:** date arithmetic from the last period start. Needs a spec entry (§11),
and must not show a due date as certain (§8).

### 10. Home-screen widget ⏳

**What:** today's cycle day at a glance.

**How:** native iOS WidgetKit extension; no allowlisted Flutter package covers
it. ❓ A widget shows on the home screen to anyone holding the phone — likely
an opt-in with a "hide details" mode.

---

## Not building, and why

| Flo feature | Why not |
|---|---|
| Account, sign-in, cloud sync | §1: no backend, no account, ever |
| Anonymous mode | Nothing to be anonymous from: there is no server |
| Community, "Secret Chats" | Needs a server |
| Health articles, AI assistant | Network content, and medical claims (§8) |
| Symptom checker, "health insights" | Diagnosis — forbidden by §8 and spec §7 |
| Partner sharing | Needs a server |
| Analytics, A/B tests | Forbidden SDKs (§6) |
| Subscription with a purchase backend | RevenueCat and similar forbidden (§6); `in_app_purchase` alone is allowed if a paid tier is ever wanted |
| "Trying to conceive" / "avoid pregnancy" guidance | Contraceptive or fertility claims (§8, spec §7) |
| Due-date countdown stated as a date | Prediction as certainty (§8) |
