# Cycle logic

The specification `CLAUDE.md` §11 refers to when it says the medical logic is
specified in the project docs and is not up to interpretation.

**Read this before writing anything in `lib/domain/logic/`.** Every rule below
states its basis, so a later reader can tell a researched decision from a guess.
Where a rule cites a study, the study is listed at the end and the rule can be
re-checked rather than taken on trust. Where a rule is a product judgement rather
than a finding, it says so.

Nothing here is a clinical guideline, and none of it may be presented to a user
as one. §8 governs all wording.

---

## 0. Why this app does not do what the others do

Three findings shaped everything below.

**Users do not know the predictions are wrong, and blame themselves.** Only
**6.4%** of surveyed users said their app always got the start date right — yet
they rarely questioned the app, attributing misses to "perceived shortcomings of
their own body" (Broad, Biswakarma & Harper 2022).

**The predictions really are that wrong.** Apps were off by as much as **8 days**
on the next period. Ovulation predictions were exactly right **8%** of the time,
with 67% landing 2–9 days early. **22.1%** of apps contained serious
inaccuracies. Most assumed a textbook 28-day cycle ovulating on day 14
(Worsfold et al. 2021).

**The textbook cycle is a minority case.** Only about **13%** of cycles are 28
days; the mean is 29.3 (Bull et al. 2019, 612,613 cycles from 124,648 users).

The conclusion this app draws: an app that states its uncertainty honestly is
both the ethical option and the differentiated one. §8 already requires windows
rather than dates; the rules below are what make that mean something rather than
being a narrow window with a hedge attached.

---

## 1. Definitions

**Period start** — a day the user explicitly marked. **Never inferred from
logged flow.** §4 makes the stored period start dates the source of truth, and
inferring starts would manufacture cycles the user never recorded, which she
would then have to hunt down and correct. The app may *offer* to mark a start
when flow is logged after a gap; it may not decide for her.

**Cycle** — from one period start to the day before the next. Length is the
number of days between consecutive starts, so 1 Jan → 29 Jan is a **28-day**
cycle. A cycle with no later start is **in progress** and has no length yet.

**Period duration** — the run of consecutive days from the period start with
flow recorded as light, medium or heavy. A day recorded as `none`, or a day with
no flow recorded at all, ends the run. FIGO puts normal duration at 2–7 days;
the app does not enforce that, it only reports what was logged.

**Completed cycle** — one with a known end. Only completed cycles feed any
statistic.

---

## 2. Which cycles count

Statistics use the **last 6 completed cycles**, after excluding logging
artifacts.

**Median, not mean.** One anomalous cycle — illness, stress, travel, a forgotten
log — should not drag the estimate. The median ignores it; the mean does not.

**Minimum 2 completed cycles** before any prediction is shown. With fewer, the
app shows what it has and says it cannot predict yet. It does not fall back to
28 days: that number is the source of the industry's error, not a safe default.

**Exclude only what is almost certainly a logging artifact:**

| Rule | Why |
|---|---|
| Length > 90 days | Almost certainly a missed period start silently merging two cycles into one |
| Length < 10 days | Almost certainly a double-logged start, or a start marked mid-period |

**Do not exclude a cycle for being physiologically unusual.** A genuine 40-day
cycle belongs to a real person, and dropping it would make her app quietly wrong
about her specifically — the exact failure this document exists to prevent. The
thresholds above are deliberately far outside any plausible human range so that
they catch data errors and nothing else.

If exclusions leave fewer than 2 cycles, the app is in the "cannot predict yet"
state.

---

## 3. Predicting the next period

    median        = median length of the eligible cycles
    spread        = interquartile spread of those lengths
    halfWidth     = max(round(spread), 1)        // days
    centre        = last period start + round(median)
    window        = [centre - halfWidth, centre + halfWidth]

    if halfWidth > 7: no prediction -- report "too variable" instead

**The window is personal, not fixed.** A user whose cycles are genuinely
consistent earns a tight window she can rely on. A user whose cycles vary gets an
honestly wide one instead of a confident wrong date. A fixed ±2 days would lie in
one direction or the other for almost everyone, and would lie worst to the
irregular users who make up most of that 6.4% figure.

**Floor of ±1 day.** Never present a single day, even for a metronomic user. §8
forbids stating a prediction as certainty, and no cycle is certain.

**Cap of ±7 days.** Past that the estimate has stopped being useful, and the app
should say the cycles are too variable to predict rather than draw a two-week
band and call it a prediction.

**Display** is a range — "26.–30." — with wording like "estimated, based on your
entries", per §8. Never a single date. Never a countdown that implies certainty.

---

## 4. The fertile window

**The highest-risk feature in the app.** Off by default; the user opts in.

### Why it is counted backwards

The phases are not equally variable:

| Phase | Mean | 95% CI |
|---|---|---|
| Follicular (start → ovulation) | 16.9 days | **10–30** |
| Luteal (ovulation → next start) | 12.4 days | **7–17** |

(Bull et al. 2019.)

Counting **forward** from the last period — what almost every competitor does —
runs the estimate through the follicular phase, whose spread is 20 days wide.
Counting **backwards** from the predicted next period runs it through the luteal
phase, which is markedly more stable. So this app counts backwards.

Wilcox et al. 2000 is the reason this matters: among women with 28-day cycles,
ovulation ranged from **day 10 to day 22**, only **10%** ovulated on day 14, and
only about **30%** had a fertile window falling entirely within the clinical days
10–17. A day-14 assumption is wrong for most people.

### The arithmetic

The fertile window is the six-day interval ending on the day of ovulation
(Wilcox et al. 2000). Ovulation is derived from the *predicted period window*, so
the uncertainty of the prediction propagates into it — an estimate built on an
estimate has to carry both, not launder one away:

    lutealMin, lutealMax = 10, 15               // days; see below
    earliestOvulation    = windowStart - lutealMax
    latestOvulation      = windowEnd   - lutealMin
    fertileWindow        = [earliestOvulation - 5, latestOvulation]

**The luteal band is ±1 SD (10–15 days), not the full 95% CI.** Using 7–17 would
be more defensible statistically and produces a window around 22 days wide, which
is honest and useless. 10–15 yields roughly 15–17 days depending on how variable
the user's cycles are. **This is a product judgement, not a finding, and it is
the one number here most worth revisiting.**

### What must always be shown alongside it

- §8's visible note that this is an estimate and **not suitable for
  contraception**.
- That the day of ovulation **cannot be determined from dates alone**. The
  research is unambiguous: without a body signal — basal body temperature, LH
  tests, cervical mucus — a calendar cannot locate ovulation.

**The only honest way to narrow this window is to add body-signal logging.** If
the fertile window is ever to be genuinely useful rather than merely honest, that
is the feature to build, not a tighter formula over the same data.

---

## 5. The irregularity hint

§8: phrased as "this might be worth mentioning to a doctor", never as a finding,
never naming a condition, never the word "abnormal".

**Shown only when all of these hold:**

- at least **3** completed eligible cycles exist, and
- either the spread between the shortest and longest of the last 6 exceeds
  **9 days**, or **2 or more** of them fall outside **24–38 days**.

24–38 days is FIGO's normal range for cycle frequency (Munro et al. 2018). The
9-day spread mirrors STRAW+10, which treats a persistent difference of **7 days
or more** between consecutive cycles as clinically meaningful — 9 is chosen as a
slightly higher bar so the hint stays rare.

**Rare on purpose.** A hint that fires every time someone has a stressful month
gets dismissed, or frightens a person whose cycle is perfectly ordinary. It earns
attention by being uncommon.

**Never** a badge, a score, a colour-coded status, or a label attached to the
user. It is one sentence, dismissible, and it does not reappear until the
condition newly becomes true again.

---

## 6. Cycle modes (§10)

Three modes where a natural cycle is absent or unreliable. In **all** of them,
logging and the calendar work exactly as normal, period starts are still
recorded, and **no prediction is computed at all** — predictions-off is a
first-class state, not a suppressed display.

| Mode | Predictions | Notes |
|---|---|---|
| **Hormonal contraception** | Off | A withdrawal bleed is scheduled by the regimen, not by a cycle. Predicting it from cycle history is meaningless. Continuous regimens may produce no bleed at all, and the app must not treat that as missing data. |
| **Pregnancy** | Off | Cycle statistics are hidden, not zeroed. Symptom logging matters more here, not less. |
| **Perimenopause** | Off by default, user may opt in | STRAW+10 defines the transition *by* rising variability, so a confident prediction is most wrong exactly where it would be most trusted. If opted in, everything is shown as ranges with the widening spread made visible rather than smoothed away. |

**Every mode states why predictions are off**, in place of where they would
otherwise appear. Silently showing nothing reads as a bug and invites the user to
conclude the app is broken.

Statistics that are pure description — cycles logged, period durations — may
still be shown in any mode. Anything predictive may not.

---

## 7. Non-goals

Stated explicitly so they are inherited rather than rediscovered:

- **No contraceptive guidance of any kind.** Not a "safe day", not a "low
  chance" day, not by colour, not by omission.
- **No diagnosis, and no condition ever named** — not PCOS, not endometriosis,
  not anything, however strongly a pattern might suggest it.
- **No treatment, medication or supplement suggestions.**
- **No prediction stated as certainty.** Always a window, always qualified.
- **No cycle-science behaviour invented in code.** If a case is not covered here,
  it goes in this document first, with its basis. That is what §11 requires.

---

## Sources

- Bull, J. R. et al. (2019). *Real-world menstrual cycle characteristics of more
  than 600,000 menstrual cycles.* npj Digital Medicine 2, 83.
  <https://www.nature.com/articles/s41746-019-0152-7>
- Wilcox, A. J., Dunson, D. & Baird, D. D. (2000). *The timing of the "fertile
  window" in the menstrual cycle: day specific estimates from a prospective
  study.* BMJ 321:1259. <https://pubmed.ncbi.nlm.nih.gov/11082088/>
- Broad, A., Biswakarma, R. & Harper, J. C. (2022). *A survey of women's
  experiences of using period tracker applications.* Women's Health 18.
  <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9047811/>
- Worsfold, L. et al. (2021). *Period tracker applications: What menstrual cycle
  information are they giving women?* Women's Health 17.
  <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8504278/>
- Munro, M. G. et al. (2018). *The two FIGO systems for normal and abnormal
  uterine bleeding.* Int J Gynecol Obstet 143:393–408.
  <https://obgyn.onlinelibrary.wiley.com/doi/full/10.1002/ijgo.12666>
- Harlow, S. D. et al. (2012). *Executive summary of the Stages of Reproductive
  Aging Workshop +10 (STRAW+10).* <https://pubmed.ncbi.nlm.nih.gov/22344196/>
