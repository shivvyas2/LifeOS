# Whoop Digest Widening Design Spec

**Date:** 2026-08-26
**Status:** Approved for planning
**Scope of this document:** Widening `MetricsDigest` so the coach can see the
Whoop data the app already ingests, plus the three ingestion gaps that widening
exposes. Covers `Insights/Context`, the two health `CoachTask` conformances,
three `Persistence` models, and the Whoop workout decode.

**Not in scope:** the cloud tier. `RemoteEngine`, the coach Edge Function, and
the spend ceiling remain unbuilt and are specified in
`2026-08-25-coach-llm-routing-design.md`. This document is the work that must
land first so that a cloud call is worth paying for.

---

## 1. What this is

The app ingests all five Whoop v2 collections. It shows the coach five numbers
a day.

`MetricsDigest.Day` carries `recoveryPct`, `sleepMinutes`, `strain`, `steps`,
`exerciseMinutes`. Stored and never surfaced to a model: HRV, resting heart
rate, SpO2, skin temperature, respiratory rate, all four sleep stages, sleep
performance, sleep efficiency, sleep need, sleep debt, every workout, every nap.

The digest is the only thing an engine is ever given, so a field absent from it
is a field the coach cannot reason about. The coach is not limited by what Whoop
gives us or by what we store. It is limited by a projection written when the
digest was a proof of concept.

This document widens that projection to everything, and fixes the three places
where widening reveals that ingestion itself drops something.

---

## 2. Decisions on record

| Decision | Choice | Rationale |
|---|---|---|
| Digest shape | One wide digest, rendered in full | Chosen over per-task rendering and over layered context types. Simplest diff; every health task sees everything |
| Field selection | All four categories: wide per-day metrics, baselines and deltas, workout and nap events, sleep need and debt | All four were asked for |
| Missing values | Absent from the render, never zero | The existing rule in `DailyMetrics`. A false zero in a health app is worse than a blank |
| Calibrating recovery | Rendered with a `(calibrating)` marker | Strictly more information than dropping it, and the model is already forbidden from inventing numbers |
| Overflow control | Drop oldest day, re-render | Keeps "render everything" intact per day. Day count is the only lever pulled |
| Zone durations | Store all six, derive `zone 3+` at render | Consistent with the archive ethos: keep the source, derive later |
| Backfill | `WhoopDerivation.rederive()` | Zero Whoop API calls. This is the case the raw archive exists for |

---

## 3. Constraint: the digest is still a privacy boundary

`MetricsDigest.swift:5` justifies the type by saying the compiler stops a raw
health record reaching a model, because `Engine.run` takes a digest.

That is now weaker than when it was written. `CoachTask` has gained
`associatedtype Context: Sendable`, so the engine accepts any `Sendable` type
and the guarantee is no longer structural.

The invariant therefore has to be stated rather than inferred:

> `MetricsDigest` and its nested types hold derived value types only. No
> `@Model` class, and no reference to one, may appear in the digest or in
> anything it stores.

`DailyMetrics`, `SleepRecord` and `WorkoutRecord` are SwiftData `@Model`
classes and are not `Sendable`. They are read in `from(...)` and never
retained. Widening the digest widens what leaves the device, which is the
reason to write this down now rather than after the cloud tier lands.

---

## 4. The widened digest

`MetricsDigest.Day` goes from five fields to roughly twenty. `Averages` keeps
its name and gains fields; renaming it to `Baselines` would churn
`MetricsDigestTests` for no behavioural gain.

```swift
public struct Day: Sendable, Equatable {
    public let date: Date

    // Unchanged
    public let recoveryPct: Int?
    public let sleepMinutes: Int?
    public let strain: Double?
    public let steps: Int?
    public let exerciseMinutes: Int?

    // Recovery detail
    public let hrvMs: Double?
    public let restingHR: Double?
    public let spo2Pct: Double?
    public let skinTempCelsius: Double?
    public let recoveryIsCalibrating: Bool?

    // Sleep detail
    public let remMinutes: Int?
    public let swsMinutes: Int?
    public let lightMinutes: Int?
    public let awakeMinutes: Int?
    public let respiratoryRate: Double?
    public let sleepPerformancePct: Double?
    public let sleepEfficiencyPct: Double?
    public let sleepNeedMinutes: Int?
    public let sleepDebtMinutes: Int?
    public let needFromStrainMinutes: Int?
    /// Total nap minutes attributed to this day, summed across every
    /// `SleepRecord` with `isNap == true`. Nil when there were none, never
    /// zero: no nap at all and a nap of unrecorded length are different facts.
    public let napMinutes: Int?

    // Events
    public let workouts: [Workout]
}

public struct Workout: Sendable, Equatable {
    public let name: String
    public let durationMinutes: Int
    public let strain: Double?
    public let averageHR: Double?
    /// Six entries, zone 0 through 5, in minutes. Nil when Whoop sent none.
    public let zoneMinutes: [Int]?
}
```

`Averages` gains `hrvMs`, `restingHR`, `strain` and `sleepDebtMinutes`
alongside the three it has. Its existing nil-rather-than-zero rule is
unchanged: an average of no readings is not an average of zero.

Night sleep and naps are separated. `sleepMinutes` and every stage figure come
from non-nap records only, via `sleepRecords(from:to:includingNaps: false)`.
`napMinutes` is the nap total. `MetricsStore.sleepRecords` already documents
why: "a nap is real, but it is not a night, and stacking it beside one misreads
the week."

### Scope of the widening

Both health tasks declare `typealias Context = MetricsDigest`, so both see the
full width. `SectorNoteTask` declares `Context = SectorEvidenceContext` and is
untouched by this change. A future task that should not see health detail opts
out by declaring a different `Context`, which is what the associated type is
for.

---

## 5. The three ingestion gaps

Each is a field Whoop sends, the app receives, and the app then discards.

### 5.1 Workout zone durations

`WhoopClient.swift:97` declines to decode `zone_durations`, on the stated
grounds that the published sample showed an empty object with no documented
member names.

The v2 OpenAPI specification documents all six as required `int64` fields:
`zone_zero_milli` through `zone_five_milli`. The comment is stale. It is
replaced by a decode.

`WorkoutRecord` gains six optional `Int` columns holding minutes. Optional
rather than defaulted, for the migration reason in 5.4. The render derives
`zone 3+` by summing zones three, four and five, because time above threshold
is the most legible single descriptor of a workout after strain.

### 5.2 Recovery calibration

`WhoopClient.swift:135` decodes `user_calibrating` into `WhoopSamples`. Nothing
reads it. `WhoopDerivation` does not persist it and `DailyMetrics` has no
column for it.

A recovery score produced while Whoop is still calibrating is not a recovery
score that supports "your recovery is down eight points". `DailyMetrics` gains
`whoopRecoveryIsCalibrating: Bool?` and the render marks it.

This is the same principle the codebase already applies to `percentRecorded` on
`WorkoutRecord`: a measurement qualified by its own reliability must not be
presented as if unqualified.

### 5.3 Sleep need components

`SleepRecord` stores `sleepNeedMinutes` and `sleepDebtMinutes`, which come from
`baseline_milli` and `need_from_sleep_debt_milli`. Whoop also sends
`need_from_recent_strain_milli` and `need_from_recent_nap_milli`.

`SleepRecord` gains `needFromStrainMinutes: Int?` and `needFromNapMinutes:
Int?`. Only the strain component reaches the digest; the nap component is
stored for completeness and is already visible through `napMinutes`.

Note that `need_from_recent_nap_milli` is negative or zero by definition: it
reduces sleep need. It is stored with its sign intact.

### 5.4 Migration and backfill

Every added column is optional. `SleepRecord.isNap` records why:

> Optional rather than a defaulted Bool, because a non-optional addition is
> what turns a lightweight migration into a store that will not open.

No re-sync is required. `WhoopDerivation.rederive()` re-reads `WhoopRawRecord`
and rebuilds derived state, so all three fields backfill across existing
history with zero Whoop API calls. Whoop rate-limits, and the archive exists
for exactly this.

---

## 6. The render

`promptLines` emits every populated field, with deltas against `averages`
inline so the model can distinguish a number from an unusual number.

```
14-day baseline: recovery 52%, sleep 7h05m, hrv 36ms, rhr 62, strain 9.4

Tue 25 Aug, recovery 51% (-1), sleep 6h40m (-25m) of 8h05m needed,
  debt +21m, from strain +8m, perf 82%, eff 91%,
  rem 1h02m, sws 1h20m, light 3h10m, awake 22m,
  strain 12.1, hrv 38ms (+2), rhr 61, spo2 95%, skin 33.7C, resp 16.1,
  steps 8420, exercise 45m
  workout: cycling 92m, strain 11.4, avg HR 141, zone 3+ 42m
```

The example is illustrative, not exhaustive: every field in Section 4 renders
when populated.

Rules:

- A nil field contributes nothing. No key, no placeholder, no zero.
- A delta appears only where the corresponding average is non-nil.
- A calibrating recovery renders as `recovery 44% (calibrating)`.
- A day with no workouts emits no workout line. Multiple workouts emit one line
  each. A nap emits `nap 38m`.
- Days render oldest first, matching the current behaviour.

---

## 7. Overflow control

### The failure this prevents

`EscalationPolicy.swift:27` maps `.exceededContextWindowSize` to `.escalate`.
`CoachRouter.runRemote` is `guard let remote else { return .unavailable }`.
`CoachViewModel.swift:143` renders `.unavailable` as "LIFO needs Apple
Intelligence on this device."

So today, a prompt too large for the on-device window tells the user their
phone is the problem. Widening the digest is the change most likely to reach
that path, so the guard ships with the widening rather than after it.

### The guard

`promptLines(budget:)` renders the full width and drops the oldest day until
the result fits, returning the widest window that does. Per-day content is
never trimmed; only the number of days changes. This preserves "render
everything" and makes the day count the single release valve.

The budget is a named constant in characters. Default: **6000 characters**,
which at roughly four characters per token leaves headroom inside a 4096-token
window once instructions, the generation schema, the question and the output
allocation are counted.

It is deliberately not derived from a token count. The on-device context window
is believed to be 4096 tokens, but that figure is not verified against the SDK
in this document, and a character budget plus a size-pinning test catches
regressions without depending on it being right. If the real figure is
established later, the constant moves and the test moves with it.

### The message

The router must distinguish "this device cannot run the model" from "this
prompt did not fit". Both currently produce `.unavailable`. The second needs
its own case or its own copy, because retrying is useless advice for the first
and correct advice for the second.

---

## 8. Call site

`MetricsDigest.from(_ rows: [DailyMetrics])` becomes:

```swift
static func from(
    metrics: [DailyMetrics],
    sleeps: [SleepRecord],
    workouts: [WorkoutRecord]
) -> MetricsDigest
```

Sleeps group onto days by `attributedDate`; workouts by
`startOfDay(for: start)`.

`CoachViewModel.swift:129` fetches all three over the same fourteen-day window.
`MetricsStore` already has `sleepRecords(from:to:)`. It has only
`workouts(on:)`, so it gains a `workouts(from:to:)` sibling; fourteen
single-day fetches for one prompt is the wrong shape.

---

## 9. Testing

Test-driven, per the project's normal workflow.

**`MetricsDigestTests`**
- A fully populated day renders every field.
- A day with nils omits those keys entirely and emits no zeros.
- Deltas appear only where the average is non-nil.
- A calibrating recovery renders with the marker.
- Workouts and naps attach to the correct day; naps stay out of `sleepMinutes`
  and the stage figures.
- The budget drops the oldest day first and never trims within a day.
- A fully populated fourteen-day digest renders under the budget. This is the
  regression pin described in Section 7.

**`WhoopWireFormatTests`**
- A `zone_durations` payload decodes to six values. The specification gives
  exact member names, so this is a real captured fixture and not a guess.

**`WhoopArchiveTests` or `WhoopDerivation` coverage**
- `rederive()` backfills zone durations, calibration and sleep need components
  from archived payloads with no network.

**`MetricsStore`**
- `workouts(from:to:)` returns the window sorted, and handles boundaries the
  same way `sleepRecords(from:to:)` does.

---

## 10. Consequences accepted

Two follow from rendering everything to every health task, and are recorded so
they are not rediscovered as surprises:

1. `AnswerTask("how many steps yesterday")` carries REM minutes and skin
   temperature. Irrelevant to that question, and sent anyway.
2. When the cloud tier lands, this full width is what is billed on every cloud
   call. At fourteen days it is affordable. It scales linearly with the window,
   so a thirty or ninety day view is a cost decision, not a rendering one.

Both are consequences of the chosen shape, not defects in it. If either becomes
painful, per-task rendering is the remedy, and the `Context` associated type
already makes it reachable without touching the router.
