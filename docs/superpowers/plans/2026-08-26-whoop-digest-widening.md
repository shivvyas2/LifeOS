# Whoop Digest Widening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the coach see the Whoop data the app already ingests, by widening `MetricsDigest` from five fields per day to the full derived surface, and by fixing the three places where ingestion itself drops a field.

**Architecture:** One wide `MetricsDigest`, rendered in full for the on-device model and in a redacted form for any future cloud tier. Three optional columns are added to `Persistence` models and backfilled from the existing raw Whoop archive with no API calls. An overflow guard drops whole days rather than trimming fields, so "render everything" stays true per day.

**Tech Stack:** Swift 6, SwiftData, Swift Testing (`import Testing`, `@Test`, `#expect`), Apple FoundationModels. Package at `LifeOSKit/`.

**Spec:** `docs/superpowers/specs/2026-08-26-whoop-digest-widening-design.md`

## Global Constraints

- **Worktree:** all work happens in `.claude/worktrees/whoop-digest-widening` on branch `docs/whoop-digest-widening`. Never commit to `main`.
- **Commits:** conventional (`type(scope): imperative summary`) with a short body explaining what and why. **No em dashes.** No Claude attribution of any kind.
- **Test command:** run from `LifeOSKit/`: `swift test --filter <SuiteName>`. Full suite: `swift test`. Baseline at plan time is 45 tests in 8 suites, all passing.
- **Every new SwiftData column is optional.** A non-optional addition turns a lightweight migration into a store that will not open (`SourceRecords.swift`, `isNap`).
- **Nil never overwrites a stored value.** Every derivation write uses `if let value = ... { record.x = value }`. A sample omitting a field means "no reading", not "clear what you had".
- **A missing value and a zero are never the same thing.** Nil renders as absent: no key, no placeholder, no zero.
- **One mapping only.** DTO to sample mapping lives on the DTO extensions in `WhoopClient.swift`, shared by the live client and `rederive()`. Never duplicate it.
- **Privacy rule (revised 2026-08-26):** HRV, SpO2, skin temperature and respiratory rate may appear in the on-device render. They must NOT appear in a render destined off-device. This replaces the blanket rule in `MetricsDigestTests.thePromptTextCarriesNoRawWhoopFields`.
- **Module boundary:** `Insights` depends on `Persistence` only. It must never import `Integrations`.

---

## File Structure

**Modified**
- `LifeOSKit/Sources/Integrations/WhoopClient.swift` - decode `zone_durations`; map three new fields
- `LifeOSKit/Sources/Integrations/WhoopSamples.swift` - three sample structs gain fields
- `LifeOSKit/Sources/Integrations/WhoopDerivation.swift` - persist the three new fields
- `LifeOSKit/Sources/Persistence/SourceRecords.swift` - `WorkoutRecord` +6 columns, `SleepRecord` +2
- `LifeOSKit/Sources/Persistence/DailyMetrics.swift` - +1 column
- `LifeOSKit/Sources/Persistence/MetricsStore.swift` - `workouts(from:to:)`; two upsert closures widen
- `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift` - the widening, the render, redaction, budget
- `LifeOSKit/Features/../CoachViewModel.swift` (app target) - call site
- `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift` - rewritten privacy test, new coverage
- `LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift` - zone fixture

**Responsibility split:** `WhoopClient` owns wire shape only. `WhoopSamples` owns neutral values. `WhoopDerivation` owns persistence. `MetricsDigest` owns projection and rendering. This plan does not move that boundary.

---

### Task 1: Workout zone durations end to end

`WhoopClient.swift:97` declines to decode `zone_durations` because member names were undocumented. The v2 spec documents all six as required `int64`. Replace the comment with a decode and carry it to the record.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift` (the `zone_durations` comment, `WorkoutRecord.Score`, the `sample` mapping)
- Modify: `LifeOSKit/Sources/Integrations/WhoopSamples.swift` (`WhoopWorkoutSample`)
- Modify: `LifeOSKit/Sources/Persistence/SourceRecords.swift` (`WorkoutRecord`)
- Modify: `LifeOSKit/Sources/Persistence/MetricsStore.swift` (`upsertWorkoutRecord` closure is caller-supplied; no signature change needed)
- Modify: `LifeOSKit/Sources/Integrations/WhoopDerivation.swift` (`storeWorkoutRecords`)
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift`

**Interfaces:**
- Produces: `WhoopWorkoutSample.zoneMinutes: [Int]?` (six entries, zone 0 through 5), `WorkoutRecord.zoneZeroMinutes` … `zoneFiveMinutes: Int?`

- [ ] **Step 1: Write the failing wire-format test**

Add to `WhoopWireFormatTests.swift`:

```swift
@Test func aWorkoutPayloadCarriesItsZoneDurations() throws {
    let json = """
    {
      "id": "ecfc6a15-4661-442f-a9a4-f160dd7afae8",
      "start": "2026-08-25T10:00:00.000Z",
      "end": "2026-08-25T11:32:00.000Z",
      "sport_name": "cycling",
      "score_state": "SCORED",
      "score": {
        "strain": 11.4,
        "kilojoule": 1569.34,
        "average_heart_rate": 141,
        "max_heart_rate": 172,
        "percent_recorded": 100.0,
        "zone_durations": {
          "zone_zero_milli": 300000,
          "zone_one_milli": 600000,
          "zone_two_milli": 900000,
          "zone_three_milli": 900000,
          "zone_four_milli": 600000,
          "zone_five_milli": 300000
        }
      }
    }
    """.data(using: .utf8)!

    let record = try WhoopClient.decoder.decode(WhoopDTOs.WorkoutRecord.self, from: json)
    let sample = try #require(record.sample)

    // 300000ms = 5min, 600000 = 10, 900000 = 15
    #expect(sample.zoneMinutes == [5, 10, 15, 15, 10, 5])
}

@Test func aWorkoutPayloadWithoutZoneDurationsDecodesToNil() throws {
    let json = """
    {
      "id": "abc", "start": "2026-08-25T10:00:00.000Z",
      "end": "2026-08-25T11:00:00.000Z", "sport_name": "running",
      "score_state": "SCORED", "score": { "strain": 8.0 }
    }
    """.data(using: .utf8)!

    let record = try WhoopClient.decoder.decode(WhoopDTOs.WorkoutRecord.self, from: json)
    let sample = try #require(record.sample)

    #expect(sample.zoneMinutes == nil)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter WhoopWireFormatTests`
Expected: FAIL, `value of type 'WhoopWorkoutSample' has no member 'zoneMinutes'`.

- [ ] **Step 3: Decode the zone durations**

In `WhoopClient.swift`, replace the `zone_durations` comment above `WorkoutRecord.Score` and add the nested type plus the field:

```swift
        struct Score: Decodable {
            let strain: Double?
            let kilojoule: Double?
            let average_heart_rate: Double?
            let max_heart_rate: Double?
            let percent_recorded: Double?
            let distance_meter: Double?
            let altitude_gain_meter: Double?
            let altitude_change_meter: Double?
            /// Documented in the v2 specification as six required int64 fields.
            /// An earlier comment here declined to decode this on the grounds
            /// that the published sample showed an empty object with no member
            /// names. The specification names all six, so it is decoded now.
            /// Still optional: a payload that omits it must degrade, not fail.
            let zone_durations: Zones?

            struct Zones: Decodable {
                let zone_zero_milli: Double?
                let zone_one_milli: Double?
                let zone_two_milli: Double?
                let zone_three_milli: Double?
                let zone_four_milli: Double?
                let zone_five_milli: Double?
            }
        }
```

- [ ] **Step 4: Carry it through the sample**

In `WhoopSamples.swift`, add to `WhoopWorkoutSample` (property, then init parameter with a `nil` default at the end of the list, then assignment):

```swift
    /// Six entries, zone 0 through 5, in minutes. Nil when Whoop sent none.
    /// An array rather than six properties because it is always all six or
    /// none, and callers sum a contiguous slice of it.
    public let zoneMinutes: [Int]?
```

Add `zoneMinutes: [Int]? = nil` as the final init parameter and `self.zoneMinutes = zoneMinutes` as the final assignment.

In `WhoopClient.swift`, extend the `WhoopDTOs.WorkoutRecord.sample` mapping with a final argument:

```swift
            zoneMinutes: score?.zone_durations.map { z in
                [z.zone_zero_milli, z.zone_one_milli, z.zone_two_milli,
                 z.zone_three_milli, z.zone_four_milli, z.zone_five_milli]
                    .map { WhoopSleepMath.minutes(fromMilliseconds: $0) ?? 0 }
            }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter WhoopWireFormatTests`
Expected: PASS.

- [ ] **Step 6: Add the six columns and persist them**

In `SourceRecords.swift`, add to `WorkoutRecord` after `sportID`:

```swift
    /// Minutes in each heart rate zone, 0 through 5. Six optional columns
    /// rather than one array because SwiftData stores scalars cleanly and an
    /// array attribute is a migration this does not need.
    public var zoneZeroMinutes: Int?
    public var zoneOneMinutes: Int?
    public var zoneTwoMinutes: Int?
    public var zoneThreeMinutes: Int?
    public var zoneFourMinutes: Int?
    public var zoneFiveMinutes: Int?
```

In `WhoopDerivation.storeWorkoutRecords`, inside the closure, after the `sportID` line:

```swift
                if let zones = sample.zoneMinutes, zones.count == 6 {
                    record.zoneZeroMinutes = zones[0]
                    record.zoneOneMinutes = zones[1]
                    record.zoneTwoMinutes = zones[2]
                    record.zoneThreeMinutes = zones[3]
                    record.zoneFourMinutes = zones[4]
                    record.zoneFiveMinutes = zones[5]
                }
```

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: PASS, 47 tests (45 baseline plus the 2 added).

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopClient.swift \
        LifeOSKit/Sources/Integrations/WhoopSamples.swift \
        LifeOSKit/Sources/Integrations/WhoopDerivation.swift \
        LifeOSKit/Sources/Persistence/SourceRecords.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift
git commit -m "feat(whoop): decode workout zone durations

The decode was skipped because the published sample showed an empty
object with no member names. The v2 specification documents all six as
required int64 fields, so the reason no longer holds.

Zone time is the most legible descriptor of a workout after strain, and
existing payloads already carry it in the raw archive, so a rederive
backfills history with no API calls."
```

---

### Task 2: Recovery calibration flag

`WhoopClient.swift:135` already decodes `user_calibrating` into `WhoopRecoverySample.isCalibrating`. Nothing persists it. A recovery score produced during calibration cannot support "your recovery is down eight points".

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/DailyMetrics.swift`
- Modify: `LifeOSKit/Sources/Integrations/WhoopDerivation.swift` (`derive`)
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopTests.swift`

**Interfaces:**
- Consumes: `WhoopRecoverySample.isCalibrating: Bool?` (already exists)
- Produces: `DailyMetrics.whoopRecoveryIsCalibrating: Bool?`

- [ ] **Step 1: Write the failing test**

Add to `WhoopTests.swift`:

```swift
@Test func aCalibratingRecoveryIsRecordedAsSuch() throws {
    let container = try LifeOSContainer.make(inMemory: true)
    let context = ModelContext(container)
    let store = MetricsStore(context: context)
    let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))
    let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    try derivation.derive(recoveries: [
        WhoopRecoverySample(date: day, recoveryPercentage: 44,
                            restingHeartRate: 64, hrvMilliseconds: 31,
                            isCalibrating: true)
    ])

    let row = try #require(try store.metrics(from: day, to: day).first)
    #expect(row.whoopRecoveryIsCalibrating == true)
    #expect(row.whoopRecoveryPct == 44)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter WhoopTests`
Expected: FAIL, `value of type 'DailyMetrics' has no member 'whoopRecoveryIsCalibrating'`.

- [ ] **Step 3: Add the column**

In `DailyMetrics.swift`, after `whoopSleepDebtMinutes`:

```swift
    /// True while Whoop is still calibrating to the user. A recovery score
    /// produced during calibration is not a score that supports a comparison,
    /// and presenting it unqualified is the same class of error as a false
    /// zero. Optional, so an existing store migrates.
    public var whoopRecoveryIsCalibrating: Bool?
```

- [ ] **Step 4: Persist it**

In `WhoopDerivation.derive`, after the `skinTempCelsius` line:

```swift
            if let value = recovery?.isCalibrating { row.whoopRecoveryIsCalibrating = value }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter WhoopTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/DailyMetrics.swift \
        LifeOSKit/Sources/Integrations/WhoopDerivation.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopTests.swift
git commit -m "feat(whoop): persist the recovery calibration flag

user_calibrating was decoded into WhoopRecoverySample and then dropped,
so nothing downstream could tell a settled recovery score from one Whoop
is still calibrating toward.

Same principle the codebase already applies to percentRecorded: a
measurement qualified by its own reliability must not be presented as if
unqualified."
```

---

### Task 3: Remaining sleep need components

`SleepRecord` stores need baseline and debt. Whoop also sends `need_from_recent_strain_milli` and `need_from_recent_nap_milli`.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift` (`SleepRecord.Score.Needed`, `sample`)
- Modify: `LifeOSKit/Sources/Integrations/WhoopSamples.swift` (`WhoopSleepSample`)
- Modify: `LifeOSKit/Sources/Persistence/SourceRecords.swift` (`SleepRecord`)
- Modify: `LifeOSKit/Sources/Integrations/WhoopDerivation.swift` (`storeSleepRecords`)
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift`

**Interfaces:**
- Produces: `WhoopSleepSample.needFromStrainMinutes: Int?`, `.needFromNapMinutes: Int?`; `SleepRecord.needFromStrainMinutes: Int?`, `.needFromNapMinutes: Int?`

- [ ] **Step 1: Write the failing test**

Add to `WhoopWireFormatTests.swift`:

```swift
@Test func aSleepPayloadCarriesEveryNeedComponent() throws {
    let json = """
    {
      "id": "s1", "cycle_id": 1,
      "start": "2026-08-25T23:00:00.000Z",
      "end": "2026-08-26T06:40:00.000Z",
      "nap": false, "score_state": "SCORED",
      "score": {
        "sleep_needed": {
          "baseline_milli": 27395716,
          "need_from_sleep_debt_milli": 1260000,
          "need_from_recent_strain_milli": 480000,
          "need_from_recent_nap_milli": -600000
        },
        "stage_summary": {
          "total_in_bed_time_milli": 27600000,
          "total_awake_time_milli": 1320000,
          "total_light_sleep_time_milli": 11400000,
          "total_rem_sleep_time_milli": 3720000,
          "total_slow_wave_sleep_time_milli": 4800000,
          "total_no_data_time_milli": 0,
          "sleep_cycle_count": 4,
          "disturbance_count": 9
        }
      }
    }
    """.data(using: .utf8)!

    let sample = try WhoopClient.decoder
        .decode(WhoopDTOs.SleepRecord.self, from: json).sample

    #expect(sample.needFromStrainMinutes == 8)     // 480000ms
    // Negative by definition: a recent nap reduces need. The sign is kept.
    #expect(sample.needFromNapMinutes == -10)      // -600000ms
    #expect(sample.sleepDebtMinutes == 21)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter WhoopWireFormatTests`
Expected: FAIL, `value of type 'WhoopSleepSample' has no member 'needFromStrainMinutes'`.

- [ ] **Step 3: Decode both components**

In `WhoopClient.swift`, extend `SleepRecord.Score.Needed`:

```swift
            struct Needed: Decodable {
                let baseline_milli: Double?
                let need_from_sleep_debt_milli: Double?
                let need_from_recent_strain_milli: Double?
                /// Negative or zero by definition: a recent nap reduces the
                /// amount of sleep still needed. The sign is preserved.
                let need_from_recent_nap_milli: Double?
            }
```

Verify `WhoopSleepMath.minutes(fromMilliseconds:)` preserves sign. It is `milli.map { Int($0 / 60_000) }`, so it does; `Int(-10.0)` is `-10`. No change needed there.

- [ ] **Step 4: Carry both through the sample**

In `WhoopSamples.swift`, add to `WhoopSleepSample` after `sleepDebtMinutes`:

```swift
    public let needFromStrainMinutes: Int?
    /// Negative or zero: a recent nap reduces need.
    public let needFromNapMinutes: Int?
```

Add `needFromStrainMinutes: Int? = nil, needFromNapMinutes: Int? = nil` as init parameters immediately after `sleepDebtMinutes`, and the two matching assignments.

In `WhoopClient.swift`, in the `SleepRecord.sample` mapping, after the `sleepDebtMinutes` argument:

```swift
            needFromStrainMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.need_from_recent_strain_milli),
            needFromNapMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.need_from_recent_nap_milli),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter WhoopWireFormatTests`
Expected: PASS.

- [ ] **Step 6: Add the columns and persist them**

In `SourceRecords.swift`, add to `SleepRecord` after `sleepDebtMinutes`:

```swift
    public var needFromStrainMinutes: Int?
    /// Negative or zero: a recent nap reduces need.
    public var needFromNapMinutes: Int?
```

In `WhoopDerivation.storeSleepRecords`, after the `sleepDebtMinutes` line:

```swift
                if let value = sample.needFromStrainMinutes { record.needFromStrainMinutes = value }
                if let value = sample.needFromNapMinutes { record.needFromNapMinutes = value }
```

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: PASS, 49 tests.

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopClient.swift \
        LifeOSKit/Sources/Integrations/WhoopSamples.swift \
        LifeOSKit/Sources/Integrations/WhoopDerivation.swift \
        LifeOSKit/Sources/Persistence/SourceRecords.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift
git commit -m "feat(whoop): store the remaining sleep need components

Only baseline and debt were kept. Whoop also reports need accrued from
recent strain and need reduced by a recent nap, which is what turns a
sleep figure into an amount actually owed tonight.

The nap component is negative by definition and is stored with its sign."
```

---

### Task 4: Range fetch for workouts

`MetricsStore` has `workouts(on:)` only. The digest needs a fortnight, and fourteen single-day fetches for one prompt is the wrong shape.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/MetricsStore.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/MetricsStoreTests.swift` (create the file if absent, with the `@Suite @MainActor struct MetricsStoreTests { }` wrapper)

**Interfaces:**
- Produces: `MetricsStore.workouts(from: Date, to: Date) throws -> [WorkoutRecord]`, oldest first, `to` inclusive of the whole day

- [ ] **Step 1: Write the failing test**

```swift
@Test func workoutsInARangeComeBackOldestFirstAndIncludeTheLastDay() throws {
    let container = try LifeOSContainer.make(inMemory: true)
    let store = MetricsStore(context: ModelContext(container))
    let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
    let second = day.addingTimeInterval(86_400)
    let outside = day.addingTimeInterval(-86_400)

    // Inserted newest first, to prove the sort is the query's doing.
    for (id, start) in [("b", second), ("a", day), ("old", outside)] {
        _ = try store.upsertWorkoutRecord(
            externalID: id, start: start.addingTimeInterval(3_600),
            durationMinutes: 30, activityName: "running"
        ) { _ in }
    }

    let found = try store.workouts(from: day, to: second)

    #expect(found.map(\.externalID) == ["a", "b"])
}
```

Note: if `upsertWorkoutRecord` is not `@discardableResult`, drop the leading `_ = `. Check its signature at `MetricsStore.swift:123` before running.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MetricsStoreTests`
Expected: FAIL, `value of type 'MetricsStore' has no member 'workouts(from:to:)'`.

- [ ] **Step 3: Add the range fetch**

In `MetricsStore.swift`, directly below `workouts(on:)`:

```swift
    /// Workouts starting within the window, oldest first. `to` is inclusive of
    /// the whole day, matching `sleepRecords(from:to:)`.
    public func workouts(from: Date, to: Date) throws -> [WorkoutRecord] {
        let start = calendar.startOfDay(for: from)
        guard let end = calendar.date(byAdding: .day, value: 1,
                                      to: calendar.startOfDay(for: to)) else { return [] }
        return try context.fetch(
            FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate { $0.start >= start && $0.start < end },
                sortBy: [SortDescriptor(\.start)]
            )
        )
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MetricsStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/MetricsStore.swift \
        LifeOSKit/Tests/PersistenceTests/MetricsStoreTests.swift
git commit -m "feat(persistence): fetch workouts over a date range

The digest needs a fortnight of workouts. Only a single-day fetch
existed, and fourteen queries to build one prompt is the wrong shape.

Boundary handling matches sleepRecords(from:to:): the end day is
included in full."
```

---

### Task 5: Widen the digest and its construction

Widen `Day` and `Averages`, and take the two source-record arrays. The render is Task 6; this task keeps `promptLines` exactly as it is so the change stays reviewable.

**Files:**
- Modify: `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift`
- Modify: the app's `CoachViewModel.swift` (call site at roughly line 129)
- Modify: `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift` (existing calls to `from`)
- Test: `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift`

**Interfaces:**
- Consumes: `MetricsStore.workouts(from:to:)` from Task 4; the columns from Tasks 1 to 3
- Produces: `MetricsDigest.from(metrics:sleeps:workouts:) -> MetricsDigest`, `MetricsDigest.Day` with the fields listed below, `MetricsDigest.Workout`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aDayCarriesTheWiderWhoopSurface() throws {
    let store = try makeStore()
    try store.upsert(date: day) {
        $0.whoopRecoveryPct = 51
        $0.hrvMs = 38
        $0.restingHR = 61
        $0.spo2Percentage = 95
        $0.skinTempCelsius = 33.7
        $0.whoopRecoveryIsCalibrating = true
    }

    let digest = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
    )

    #expect(digest.days[0].hrvMs == 38)
    #expect(digest.days[0].restingHR == 61)
    #expect(digest.days[0].spo2Pct == 95)
    #expect(digest.days[0].skinTempCelsius == 33.7)
    #expect(digest.days[0].recoveryIsCalibrating == true)
}

@Test func nightSleepAndNapsStaySeparate() throws {
    let store = try makeStore()
    let night = SleepRecord(externalID: "n", start: day.addingTimeInterval(-3_600),
                            end: day.addingTimeInterval(21_600), attributedDate: day)
    night.remMinutes = 62
    night.swsMinutes = 80
    night.isNap = false
    let nap = SleepRecord(externalID: "p", start: day.addingTimeInterval(50_000),
                          end: day.addingTimeInterval(52_280), attributedDate: day)
    nap.isNap = true

    let digest = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: day),
        sleeps: [night, nap], workouts: []
    )

    #expect(digest.days[0].remMinutes == 62)
    #expect(digest.days[0].swsMinutes == 80)
    #expect(digest.days[0].napMinutes == 38)   // 2280s
}

@Test func aDayWithNoNapReportsNilRatherThanZero() throws {
    let store = try makeStore()
    try store.upsert(date: day) { $0.steps = 100 }

    let digest = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
    )

    #expect(digest.days[0].napMinutes == nil)
}

@Test func workoutsAttachToTheDayTheyStarted() throws {
    let store = try makeStore()
    let second = day.addingTimeInterval(86_400)
    let record = WorkoutRecord(externalID: "w", start: second.addingTimeInterval(3_600),
                               durationMinutes: 92, activityName: "cycling")
    record.strain = 11.4
    record.zoneThreeMinutes = 20
    record.zoneFourMinutes = 15
    record.zoneFiveMinutes = 7

    let digest = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: second), sleeps: [], workouts: [record]
    )

    #expect(digest.days[0].workouts.isEmpty)
    #expect(digest.days[1].workouts.count == 1)
    #expect(digest.days[1].workouts[0].name == "cycling")
    #expect(digest.days[1].workouts[0].zoneMinutes == [0, 0, 0, 20, 15, 7])
}
```

Also update every existing caller. These are all of them:

- `MetricsDigestTests.swift` lines 20, 32, 45, 55, 73
- `CoachTaskTests.swift` line 17
- `CoachViewModel.swift` line 130 (Step 5 below)

Each becomes `MetricsDigest.from(metrics: try store.metrics(...), sleeps: [], workouts: [])`.

`CoachRouterTests.swift:32` also breaks, because `Averages` gains four fields:

```swift
    private let empty = MetricsDigest(
        days: [],
        averages: MetricsDigest.Averages(
            recoveryPct: nil, sleepMinutes: nil, steps: nil,
            hrvMs: nil, restingHR: nil, strain: nil, sleepDebtMinutes: nil
        )
    )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MetricsDigestTests`
Expected: FAIL, no `from(metrics:sleeps:workouts:)` overload.

- [ ] **Step 3: Widen `Day`, add `Workout`, widen `Averages`**

Replace the `Day` and `Averages` declarations in `MetricsDigest.swift`:

```swift
    public struct Workout: Sendable, Equatable {
        public let name: String
        public let durationMinutes: Int
        public let strain: Double?
        public let averageHR: Double?
        /// Six entries, zone 0 through 5, in minutes. Nil when none were stored.
        public let zoneMinutes: [Int]?

        /// Time at or above zone three. The single most legible descriptor of a
        /// workout after strain.
        public var highZoneMinutes: Int? {
            zoneMinutes.map { $0[3] + $0[4] + $0[5] }
        }
    }

    public struct Day: Sendable, Equatable {
        public let date: Date

        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let strain: Double?
        public let steps: Int?
        public let exerciseMinutes: Int?

        public let hrvMs: Double?
        public let restingHR: Double?
        public let spo2Pct: Double?
        public let skinTempCelsius: Double?
        public let recoveryIsCalibrating: Bool?

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
        /// Total nap minutes for this day, summed across every nap record. Nil
        /// when there were none, never zero: no nap at all and a nap of
        /// unrecorded length are different facts.
        public let napMinutes: Int?

        public let workouts: [Workout]
    }

    public struct Averages: Sendable, Equatable {
        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let steps: Int?
        public let hrvMs: Double?
        public let restingHR: Double?
        public let strain: Double?
        public let sleepDebtMinutes: Int?
    }
```

- [ ] **Step 4: Rewrite `from`**

Replace the existing `from(_:)` with:

```swift
    public static func from(
        metrics: [DailyMetrics],
        sleeps: [SleepRecord],
        workouts: [WorkoutRecord],
        calendar: Calendar = .current
    ) -> MetricsDigest {
        // Naps never contribute to the night. `MetricsStore.sleepRecords`
        // records why: a nap is real, but it is not a night, and stacking it
        // beside one misreads the week.
        let nights = Dictionary(
            grouping: sleeps.filter { $0.isNap != true },
            by: { calendar.startOfDay(for: $0.attributedDate) }
        )
        let naps = Dictionary(
            grouping: sleeps.filter { $0.isNap == true },
            by: { calendar.startOfDay(for: $0.attributedDate) }
        )
        let workoutsByDay = Dictionary(
            grouping: workouts,
            by: { calendar.startOfDay(for: $0.start) }
        )

        let days = metrics
            .sorted { $0.date < $1.date }
            .map { row -> Day in
                let key = calendar.startOfDay(for: row.date)
                let night = nights[key]?.first
                let dayNaps = naps[key] ?? []

                return Day(
                    date: row.date,
                    recoveryPct: row.whoopRecoveryPct.map { Int($0.rounded()) },
                    sleepMinutes: row.sleepMinutes,
                    strain: row.whoopDayStrain,
                    steps: row.steps,
                    exerciseMinutes: row.exerciseMinutes,
                    hrvMs: row.hrvMs,
                    restingHR: row.restingHR,
                    spo2Pct: row.spo2Percentage,
                    skinTempCelsius: row.skinTempCelsius,
                    recoveryIsCalibrating: row.whoopRecoveryIsCalibrating,
                    remMinutes: night?.remMinutes,
                    swsMinutes: night?.swsMinutes,
                    lightMinutes: night?.lightMinutes,
                    awakeMinutes: night?.awakeMinutes,
                    respiratoryRate: row.respiratoryRate,
                    sleepPerformancePct: row.whoopSleepPerformancePct,
                    sleepEfficiencyPct: row.whoopSleepEfficiencyPct,
                    sleepNeedMinutes: night?.sleepNeedMinutes,
                    sleepDebtMinutes: row.whoopSleepDebtMinutes,
                    needFromStrainMinutes: night?.needFromStrainMinutes,
                    // Nil, not zero, when the day had no nap at all.
                    napMinutes: dayNaps.isEmpty
                        ? nil
                        : dayNaps.reduce(0) { $0 + $1.durationMinutes },
                    workouts: (workoutsByDay[key] ?? []).map { w in
                        Workout(
                            name: w.activityName,
                            durationMinutes: w.durationMinutes,
                            strain: w.strain,
                            averageHR: w.averageHR,
                            zoneMinutes: [
                                w.zoneZeroMinutes, w.zoneOneMinutes, w.zoneTwoMinutes,
                                w.zoneThreeMinutes, w.zoneFourMinutes, w.zoneFiveMinutes
                            ].contains(where: { $0 != nil })
                                ? [w.zoneZeroMinutes ?? 0, w.zoneOneMinutes ?? 0,
                                   w.zoneTwoMinutes ?? 0, w.zoneThreeMinutes ?? 0,
                                   w.zoneFourMinutes ?? 0, w.zoneFiveMinutes ?? 0]
                                : nil
                        )
                    }
                )
            }

        return MetricsDigest(
            days: days,
            averages: Averages(
                recoveryPct: average(days.compactMap(\.recoveryPct)),
                sleepMinutes: average(days.compactMap(\.sleepMinutes)),
                steps: average(days.compactMap(\.steps)),
                hrvMs: average(days.compactMap(\.hrvMs)),
                restingHR: average(days.compactMap(\.restingHR)),
                strain: average(days.compactMap(\.strain)),
                sleepDebtMinutes: average(days.compactMap(\.sleepDebtMinutes))
            )
        )
    }

    /// Nil rather than zero when nothing contributed: an average of no
    /// readings is not an average of zero.
    private static func average(_ values: [Double]) -> Double? {
        guard values.isEmpty == false else { return nil }
        return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }
```

Keep the existing `average(_ values: [Int]) -> Int?` alongside the new `Double` overload.

- [ ] **Step 5: Update the app call site**

In `CoachViewModel.swift`, replace the digest construction (roughly lines 127 to 130):

```swift
            let metricsStore = MetricsStore(context: context)
            let rows = try metricsStore.metrics(from: start, to: end)
            let digest = MetricsDigest.from(
                metrics: rows,
                sleeps: try metricsStore.sleepRecords(from: start, to: end),
                workouts: try metricsStore.workouts(from: start, to: end)
            )
```

Line 130 is the only app-target call site; it was verified at plan time with `grep -rn "MetricsDigest.from" LIfeOS/`. Re-run that grep after editing to confirm nothing remains.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter MetricsDigestTests`
Expected: PASS. `thePromptTextCarriesNoRawWhoopFields` still passes at this point, because the render has not changed yet. It is rewritten in Task 7.

- [ ] **Step 7: Build the app target**

Run: `xcodebuild -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED. This catches call sites `swift test` cannot see.

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Insights/Context/MetricsDigest.swift \
        LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift \
        LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift
git commit -m "feat(insights): widen the digest to the full derived surface

The digest carried five numbers a day while the app stored HRV, resting
HR, SpO2, skin temperature, sleep stages, sleep need and every workout.
A field absent from the digest is a field the coach cannot reason about,
so the coach was limited by the projection rather than by the data.

Construction now takes sleep and workout records alongside the daily
rows. Naps are summed separately and never contribute to the night."
```

---

### Task 6: Render the full width

**Files:**
- Modify: `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift` (`promptLines`)
- Test: `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift`

**Interfaces:**
- Consumes: `Day` and `Averages` from Task 5
- Produces: `MetricsDigest.promptLines: String` rendering every populated field, with a leading baseline line

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theRenderCarriesEveryPopulatedFieldAndOmitsTheRest() throws {
    let store = try makeStore()
    try store.upsert(date: day) {
        $0.whoopRecoveryPct = 51
        $0.hrvMs = 38
        $0.whoopDayStrain = 12.1
        // steps deliberately absent
    }

    let text = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
    ).promptLines

    #expect(text.contains("recovery 51%"))
    #expect(text.contains("hrv 38ms"))
    #expect(text.contains("strain 12.1"))
    #expect(text.contains("steps") == false)   // absent, not "steps 0"
}

@Test func aCalibratingRecoveryIsMarkedInTheRender() throws {
    let store = try makeStore()
    try store.upsert(date: day) {
        $0.whoopRecoveryPct = 44
        $0.whoopRecoveryIsCalibrating = true
    }

    let text = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
    ).promptLines

    #expect(text.contains("recovery 44% (calibrating)"))
}

@Test func aDeltaAppearsOnlyWhereAnAverageExists() throws {
    let store = try makeStore()
    let second = day.addingTimeInterval(86_400)
    try store.upsert(date: day) { $0.whoopRecoveryPct = 60 }
    try store.upsert(date: second) { $0.whoopRecoveryPct = 40 }

    let text = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: second), sleeps: [], workouts: []
    ).promptLines

    #expect(text.contains("14-day baseline"))
    #expect(text.contains("recovery 60% (+10)"))
    #expect(text.contains("recovery 40% (-10)"))
}

@Test func aWorkoutRendersItsHighZoneTime() throws {
    let store = try makeStore()
    try store.upsert(date: day) { $0.steps = 100 }
    let record = WorkoutRecord(externalID: "w", start: day.addingTimeInterval(3_600),
                               durationMinutes: 92, activityName: "cycling")
    record.strain = 11.4
    record.averageHR = 141
    record.zoneThreeMinutes = 20
    record.zoneFourMinutes = 15
    record.zoneFiveMinutes = 7

    let text = MetricsDigest.from(
        metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: [record]
    ).promptLines

    #expect(text.contains("workout: cycling 92m"))
    #expect(text.contains("strain 11.4"))
    #expect(text.contains("zone 3+ 42m"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MetricsDigestTests`
Expected: FAIL on the new assertions. `thePromptTextCarriesNoRawWhoopFields` will ALSO fail once `hrv` renders. That is expected and correct; it is replaced in Task 7. Do not delete it yet, and do not let its failure block this task's own assertions from being verified.

- [ ] **Step 3: Implement the render**

Replace `promptLines` in `MetricsDigest.swift`:

```swift
    /// The digest as the model sees it. One block per day, omitting anything
    /// missing rather than writing "nil": a blank costs no tokens and says the
    /// same thing. Deltas against the baseline are what let the model tell a
    /// number from an unusual number.
    public var promptLines: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"

        var blocks: [String] = []
        if let baseline = baselineLine { blocks.append(baseline + "\n") }
        blocks.append(contentsOf: days.map { render($0, formatter) })
        return blocks.joined(separator: "\n")
    }

    private var baselineLine: String? {
        var parts: [String] = []
        if let v = averages.recoveryPct { parts.append("recovery \(v)%") }
        if let v = averages.sleepMinutes { parts.append("sleep \(duration(v))") }
        if let v = averages.hrvMs { parts.append("hrv \(number(v))ms") }
        if let v = averages.restingHR { parts.append("rhr \(number(v))") }
        if let v = averages.strain { parts.append("strain \(number(v))") }
        if let v = averages.steps { parts.append("steps \(v)") }
        guard parts.isEmpty == false else { return nil }
        return "\(days.count)-day baseline: " + parts.joined(separator: ", ")
    }

    private func render(_ day: Day, _ formatter: DateFormatter) -> String {
        var parts: [String] = [formatter.string(from: day.date)]

        if let v = day.recoveryPct {
            var text = "recovery \(v)%\(delta(v, averages.recoveryPct))"
            // A score produced while Whoop is calibrating is not a score that
            // supports a comparison. Marking it is strictly more information
            // than dropping it.
            if day.recoveryIsCalibrating == true { text += " (calibrating)" }
            parts.append(text)
        }
        if let v = day.sleepMinutes {
            var text = "sleep \(duration(v))\(deltaMinutes(v, averages.sleepMinutes))"
            if let need = day.sleepNeedMinutes { text += " of \(duration(need)) needed" }
            parts.append(text)
        }
        if let v = day.sleepDebtMinutes { parts.append("debt \(signed(v))m") }
        if let v = day.needFromStrainMinutes { parts.append("from strain \(signed(v))m") }
        if let v = day.sleepPerformancePct { parts.append("perf \(number(v))%") }
        if let v = day.sleepEfficiencyPct { parts.append("eff \(number(v))%") }
        if let v = day.remMinutes { parts.append("rem \(duration(v))") }
        if let v = day.swsMinutes { parts.append("sws \(duration(v))") }
        if let v = day.lightMinutes { parts.append("light \(duration(v))") }
        if let v = day.awakeMinutes { parts.append("awake \(duration(v))") }
        if let v = day.napMinutes { parts.append("nap \(duration(v))") }
        if let v = day.strain { parts.append("strain \(number(v))\(delta(v, averages.strain))") }
        if let v = day.hrvMs { parts.append("hrv \(number(v))ms\(delta(v, averages.hrvMs))") }
        if let v = day.restingHR { parts.append("rhr \(number(v))\(delta(v, averages.restingHR))") }
        if let v = day.spo2Pct { parts.append("spo2 \(number(v))%") }
        if let v = day.skinTempCelsius { parts.append("skin \(number(v))C") }
        if let v = day.respiratoryRate { parts.append("resp \(number(v))") }
        if let v = day.steps { parts.append("steps \(v)") }
        if let v = day.exerciseMinutes { parts.append("exercise \(v)m") }

        var block = parts.joined(separator: ", ")
        for workout in day.workouts {
            var w = ["workout: \(workout.name) \(workout.durationMinutes)m"]
            if let v = workout.strain { w.append("strain \(number(v))") }
            if let v = workout.averageHR { w.append("avg HR \(number(v))") }
            if let v = workout.highZoneMinutes, v > 0 { w.append("zone 3+ \(v)m") }
            block += "\n  " + w.joined(separator: ", ")
        }
        return block
    }

    // Formatting helpers. Kept private and tiny: the render is the only caller.

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
                      : "\(minutes)m"
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    /// Empty when there is no baseline to compare against, so a delta never
    /// implies a comparison that was not made.
    private func delta(_ value: Int, _ average: Int?) -> String {
        guard let average, average != value else { return "" }
        return " (\(signed(value - average)))"
    }

    private func delta(_ value: Double, _ average: Double?) -> String {
        guard let average else { return "" }
        let difference = ((value - average) * 10).rounded() / 10
        guard difference != 0 else { return "" }
        return difference > 0 ? " (+\(number(difference)))" : " (\(number(difference)))"
    }

    private func deltaMinutes(_ value: Int, _ average: Int?) -> String {
        guard let average, average != value else { return "" }
        let difference = value - average
        return " (\(difference >= 0 ? "+" : "-")\(duration(abs(difference))))"
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter MetricsDigestTests`
Expected: the four new tests PASS. `thePromptTextCarriesNoRawWhoopFields` FAILS. That single expected failure is carried into Task 7 and resolved there.

- [ ] **Step 5: Commit**

Commit with the known failing test, because splitting the render from its test rewrite would mean committing a render nobody can read:

```bash
git add LifeOSKit/Sources/Insights/Context/MetricsDigest.swift \
        LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift
git commit -m "feat(insights): render the full digest width

Every populated field now reaches the model, with deltas against the
baseline so it can tell a number from an unusual number, and a
calibrating marker so a provisional recovery score is not read as a
settled one.

thePromptTextCarriesNoRawWhoopFields fails at this commit by design. It
asserts a blanket rule that the next commit narrows to off-device
renders, which is where the rule actually bites."
```

---

### Task 7: Scope the privacy rule to off-device renders

The rule stays mechanical, but applies where data leaves the phone. On-device, nothing leaves.

**Files:**
- Modify: `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift`
- Modify: `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift`

**Interfaces:**
- Produces: `MetricsDigest.Audience` (`.onDevice`, `.offDevice`), `MetricsDigest.promptLines(for:) -> String`. `promptLines` remains as a property defaulting to `.onDevice`, so Task 6's callers and tests are unchanged.

- [ ] **Step 1: Rewrite the privacy test**

Replace `thePromptTextCarriesNoRawWhoopFields` entirely with:

```swift
    /// The privacy rule, scoped to where it bites. HRV, SpO2, skin temperature
    /// and respiratory rate are fine on-device, where nothing leaves the phone.
    /// They must not appear in a render destined for a provider.
    ///
    /// Revised 2026-08-26. The blanket version of this test predated any
    /// off-device path and blocked the on-device coach from data already on
    /// the device.
    @Test func anOffDeviceRenderCarriesNoRawWhoopSeries() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.steps = 8_000
            $0.whoopRecoveryPct = 62
            $0.hrvMs = 41.2
            $0.spo2Percentage = 97.5
            $0.skinTempCelsius = 33.4
            $0.respiratoryRate = 14.2
        }
        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        let offDevice = digest.promptLines(for: .offDevice)

        #expect(offDevice.contains("62"))              // the aggregate is wanted
        #expect(offDevice.contains("41.2") == false)   // HRV series is not
        #expect(offDevice.contains("97.5") == false)
        #expect(offDevice.contains("33.4") == false)
        #expect(offDevice.contains("14.2") == false)
    }

    @Test func anOnDeviceRenderCarriesTheSeries() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.hrvMs = 41.2
            $0.spo2Percentage = 97.5
        }
        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.promptLines(for: .onDevice).contains("41.2"))
        #expect(digest.promptLines.contains("97.5"))   // the property defaults to on-device
    }
```

- [ ] **Step 2: Run to verify the new test fails**

Run: `swift test --filter MetricsDigestTests`
Expected: FAIL, no `promptLines(for:)` member.

- [ ] **Step 3: Add the audience and gate the four fields**

In `MetricsDigest.swift`, add the enum inside the struct:

```swift
    /// Who the render is for. The distinction exists because the raw Whoop
    /// series stays on the phone: on-device inference sends nothing anywhere,
    /// and a provider call does.
    public enum Audience: Sendable {
        case onDevice
        case offDevice
    }
```

Change `promptLines` to a method plus a defaulting property:

```swift
    public var promptLines: String { promptLines(for: .onDevice) }

    public func promptLines(for audience: Audience) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"

        var blocks: [String] = []
        if let baseline = baselineLine(for: audience) { blocks.append(baseline + "\n") }
        blocks.append(contentsOf: days.map { render($0, formatter, audience) })
        return blocks.joined(separator: "\n")
    }
```

Thread `audience` into `render` and `baselineLine`, and gate the four series. In `render`, replace the four unconditional lines with:

```swift
        if audience == .onDevice {
            if let v = day.hrvMs { parts.append("hrv \(number(v))ms\(delta(v, averages.hrvMs))") }
            if let v = day.spo2Pct { parts.append("spo2 \(number(v))%") }
            if let v = day.skinTempCelsius { parts.append("skin \(number(v))C") }
            if let v = day.respiratoryRate { parts.append("resp \(number(v))") }
        }
```

In `baselineLine`, gate the HRV line the same way:

```swift
        if audience == .onDevice, let v = averages.hrvMs { parts.append("hrv \(number(v))ms") }
```

Resting heart rate stays in both: it is a single daily aggregate of the kind the original test explicitly allowed through, not a raw series.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter MetricsDigestTests`
Expected: PASS, including the two rewritten privacy tests.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS, all suites green.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Insights/Context/MetricsDigest.swift \
        LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift
git commit -m "feat(insights): scope the raw series rule to off-device renders

The rule was blanket: HRV, SpO2, skin temperature and respiratory rate
could not appear in any prompt. It predated any off-device path, so it
was withholding data from a model running on the phone that holds it.

Now the digest renders for an audience. On-device gets everything.
Off-device omits the four raw series, which is where sending actually
happens and where the rule was always aimed."
```

---

### Task 8: Overflow guard

A widened prompt can exceed the on-device window. Today that escalates to a cloud engine that does not exist and surfaces as "LIFO needs Apple Intelligence on this device", blaming the wrong thing.

**Files:**
- Modify: `LifeOSKit/Sources/Insights/Context/MetricsDigest.swift`
- Test: `LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift`

**Interfaces:**
- Produces: `MetricsDigest.promptBudget: Int` (6000), `promptLines(for:budget:) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theRenderDropsWholeDaysOldestFirstToFitTheBudget() throws {
    let store = try makeStore()
    var dates: [Date] = []
    for offset in 0..<14 {
        let d = day.addingTimeInterval(Double(offset) * 86_400)
        dates.append(d)
        try store.upsert(date: d) {
            $0.whoopRecoveryPct = 50 + Double(offset)
            $0.steps = 8_000
        }
    }
    let digest = MetricsDigest.from(
        metrics: try store.metrics(from: dates.first!, to: dates.last!),
        sleeps: [], workouts: []
    )

    let full = digest.promptLines(for: .onDevice, budget: 100_000)
    let squeezed = digest.promptLines(for: .onDevice, budget: 300)

    #expect(squeezed.count <= 300)
    #expect(squeezed.count < full.count)
    // The newest day survives; the oldest is what goes.
    #expect(squeezed.contains("recovery 63%"))
    #expect(squeezed.contains("recovery 50%") == false)
}

/// The regression pin. A fully populated fortnight must fit the real budget.
@Test func aFullyPopulatedFortnightFitsTheBudget() throws {
    let store = try makeStore()
    var dates: [Date] = []
    var sleeps: [SleepRecord] = []
    var workouts: [WorkoutRecord] = []

    for offset in 0..<14 {
        let d = day.addingTimeInterval(Double(offset) * 86_400)
        dates.append(d)
        try store.upsert(date: d) {
            $0.whoopRecoveryPct = 51; $0.sleepMinutes = 400; $0.whoopDayStrain = 12.1
            $0.steps = 8_420; $0.exerciseMinutes = 45; $0.hrvMs = 38; $0.restingHR = 61
            $0.spo2Percentage = 95; $0.skinTempCelsius = 33.7; $0.respiratoryRate = 16.1
            $0.whoopSleepPerformancePct = 82; $0.whoopSleepEfficiencyPct = 91
            $0.whoopSleepDebtMinutes = 21
        }
        let night = SleepRecord(externalID: "n\(offset)", start: d, end: d.addingTimeInterval(24_000),
                                attributedDate: d)
        night.remMinutes = 62; night.swsMinutes = 80; night.lightMinutes = 190
        night.awakeMinutes = 22; night.sleepNeedMinutes = 485
        night.needFromStrainMinutes = 8; night.isNap = false
        sleeps.append(night)

        let w = WorkoutRecord(externalID: "w\(offset)", start: d.addingTimeInterval(3_600),
                              durationMinutes: 92, activityName: "cycling")
        w.strain = 11.4; w.averageHR = 141
        w.zoneThreeMinutes = 20; w.zoneFourMinutes = 15; w.zoneFiveMinutes = 7
        workouts.append(w)
    }

    let digest = MetricsDigest.from(
        metrics: try store.metrics(from: dates.first!, to: dates.last!),
        sleeps: sleeps, workouts: workouts
    )

    let text = digest.promptLines(for: .onDevice, budget: MetricsDigest.promptBudget)

    // Nothing was dropped: all fourteen days survive at the real budget.
    #expect(text.contains("rem 1h02m"))
    #expect(digest.days.count == 14)
    #expect(text.count <= MetricsDigest.promptBudget)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter MetricsDigestTests`
Expected: FAIL, no `promptBudget` / no `budget:` parameter.

- [ ] **Step 3: Implement the budget**

In `MetricsDigest.swift`:

```swift
    /// Characters, not tokens. The on-device context window is believed to be
    /// 4096 tokens, but that figure is not verified against the SDK, and a
    /// character budget plus a size-pinning test catches regressions without
    /// depending on it being right. At roughly four characters per token this
    /// leaves room for instructions, the generation schema, the question and
    /// the output allocation.
    public static let promptBudget = 6_000

    public func promptLines(for audience: Audience, budget: Int = MetricsDigest.promptBudget) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"

        // Whole days are dropped rather than fields trimmed, so a day that
        // renders at all renders completely. Oldest goes first: the newest day
        // is the one a brief is about.
        var window = days
        while true {
            let text = assemble(window, formatter, audience)
            if text.count <= budget || window.count <= 1 { return text }
            window.removeFirst()
        }
    }

    private func assemble(_ window: [Day], _ formatter: DateFormatter, _ audience: Audience) -> String {
        var blocks: [String] = []
        if let baseline = baselineLine(for: audience) { blocks.append(baseline + "\n") }
        blocks.append(contentsOf: window.map { render($0, formatter, audience) })
        return blocks.joined(separator: "\n")
    }
```

`promptLines(for:)` from Task 7 is now this method with a defaulted `budget`, so no other caller changes.

Note the baseline line still says `\(days.count)-day baseline` and is computed over every day, including any that were dropped from the render. That is intentional: the baseline is a fact about the fortnight, not about what fitted.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter MetricsDigestTests`
Expected: PASS. If `aFullyPopulatedFortnightFitsTheBudget` fails on `text.count <= promptBudget`, the render is fatter than estimated. Raise `promptBudget` only after checking that the render has no accidental repetition; the test exists to force that check, not to be edited away.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Insights/Context/MetricsDigest.swift \
        LifeOSKit/Tests/InsightsTests/MetricsDigestTests.swift
git commit -m "feat(insights): cap the rendered prompt by dropping whole days

Widening the digest made an oversized prompt reachable. Days are dropped
oldest first rather than fields trimmed, so a day that renders at all
renders completely, and the newest day is never the one that goes.

The budget is in characters. The on-device window is believed to be 4096
tokens but that is unverified, so a pinned size test guards the
regression without depending on the figure."
```

---

### Task 9: Tell the truth when a prompt does not fit

`CoachRouter` maps both "no on-device model" and "prompt too large" to `.unavailable`, and the view says the device lacks Apple Intelligence. Retrying is useless advice for the first and correct for the second.

**Files:**
- Modify: `LifeOSKit/Sources/Insights/CoachRouter.swift`
- Modify: `LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift`
- Test: `LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift`

**Interfaces:**
- Consumes: `CoachResult` from `CoachRouter.swift`
- Produces: `CoachResult.tooLarge` case

- [ ] **Step 1: Write the failing test**

Add to `LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift`, inside `@Suite struct CoachRouterTests`. It uses the file's existing `router(onDevice:remote:availability:)` helper, its `empty` digest and its `context` property, so no new stub type is needed:

```swift
    /// An oversized prompt is our fault and is fixed by sending less. Telling
    /// the user their device lacks Apple Intelligence sends them to a settings
    /// screen that will not help.
    @Test func anOversizedPromptIsReportedAsSuchRatherThanAsAMissingModel() async throws {
        let router = router(
            onDevice: { throw LanguageModelSession.GenerationError.exceededContextWindowSize(context) },
            remote: nil
        )

        let result = await router.run(BriefTask(), empty)

        #expect(result == .tooLarge)
    }
```

Check the exact `GenerationError` construction against a neighbouring test in the same file before running; the file already builds these errors and the associated-value shape must match what it uses.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CoachRouterTests`
Expected: FAIL, `type 'CoachResult' has no member 'tooLarge'`.

- [ ] **Step 3: Add the case and route to it**

In `CoachRouter.swift`, add to `CoachResult`:

```swift
    /// The prompt did not fit and there is no larger tier to send it to.
    /// Distinct from `unavailable`, which means no model could run at all:
    /// this one is our fault and is fixed by sending less, not by the user
    /// changing a device setting.
    case tooLarge
```

In `runLocal`, the `.escalate` branch must remember why it escalated:

```swift
            case .escalate:
                if case .exceededContextWindowSize = error {
                    return await runRemote(task, context, fallback: .tooLarge)
                }
                return await runRemote(task, context)
```

Give `runRemote` a `fallback` parameter defaulting to `.unavailable`, and use it in both the missing-engine guard and the catch:

```swift
    private func runRemote<T: CoachTask>(
        _ task: T,
        _ context: T.Context,
        fallback: CoachResult<T.Output> = .unavailable
    ) async -> CoachResult<T.Output> {
        guard let remote else { return fallback }
        do {
            return .answered(try await remote.run(task, context))
        } catch {
            return fallback
        }
    }
```

- [ ] **Step 4: Handle it in the view model**

In `CoachViewModel.swift`, add a case to each `switch` over `CoachResult` (the `send` method and any brief path):

```swift
            case .tooLarge:
                fail("That covered too much at once. Try asking about a shorter stretch.")
```

Swift will flag every non-exhaustive switch, so the compiler finds the sites.

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter CoachRouterTests`
Expected: PASS.

- [ ] **Step 6: Run the full suite and build the app**

Run: `swift test`
Expected: PASS.

Run: `xcodebuild -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Insights/CoachRouter.swift \
        LifeOSKit/Tests/InsightsTests/CoachRouterTests.swift \
        LIfeOS/Features/Coach/ViewModel/CoachViewModel.swift
git commit -m "fix(coach): stop blaming the device for an oversized prompt

A prompt too large for the on-device window escalated to a cloud engine
that does not exist yet, fell through to unavailable, and told the user
their phone needs Apple Intelligence. The phone was fine.

tooLarge is now its own result, so the copy can say what actually
happened and offer advice that works."
```

---

### Task 10: Backfill from the archive

All three ingestion fields exist in payloads already stored. Prove a rebuild fills them with no network.

**Files:**
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 to 3, plus `WhoopDerivation.rederive()`

- [ ] **Step 1: Write the failing test**

```swift
@Test func aRederiveBackfillsTheNewFieldsFromTheArchiveAlone() throws {
    let container = try LifeOSContainer.make(inMemory: true)
    let context = ModelContext(container)
    let store = MetricsStore(context: context)
    let archive = WhoopArchive(context: context)
    let derivation = WhoopDerivation(store: store, archive: archive)

    let workout = """
    {"id":"w1","start":"2026-08-25T10:00:00.000Z","end":"2026-08-25T11:32:00.000Z",
     "sport_name":"cycling","score_state":"SCORED",
     "score":{"strain":11.4,"zone_durations":{"zone_zero_milli":0,"zone_one_milli":0,
     "zone_two_milli":0,"zone_three_milli":1200000,"zone_four_milli":900000,
     "zone_five_milli":420000}}}
    """.data(using: .utf8)!
    let recovery = """
    {"created_at":"2026-08-25T11:00:00.000Z","score_state":"SCORED",
     "score":{"recovery_score":44,"resting_heart_rate":64,"hrv_rmssd_milli":31,
     "user_calibrating":true}}
    """.data(using: .utf8)!

    try archive.store(kind: "workout", externalID: "w1", payload: workout)
    try archive.store(kind: "recovery", externalID: "r1", payload: recovery)

    try derivation.rederive()

    let dayOf = Calendar.current.startOfDay(for: ISO8601DateFormatter()
        .date(from: "2026-08-25T11:00:00Z")!)
    let row = try #require(try store.metrics(from: dayOf, to: dayOf).first)
    #expect(row.whoopRecoveryIsCalibrating == true)

    let found = try #require(try store.workouts(from: dayOf, to: dayOf).first)
    #expect(found.zoneThreeMinutes == 20)
    #expect(found.zoneFourMinutes == 15)
    #expect(found.zoneFiveMinutes == 7)
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter WhoopTests`
Expected: PASS immediately, because Tasks 1 to 3 already wired the mapping through the shared DTO extensions that `rederive` uses. If it FAILS, a mapping was duplicated rather than shared; fix the mapping rather than the test.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add LifeOSKit/Tests/IntegrationsTests/WhoopTests.swift
git commit -m "test(whoop): pin that a rederive backfills the new fields

The three added fields have to reach existing history without asking
Whoop for it again, which is the whole reason the raw archive exists.
This proves it from archived payloads with no network."
```

---

## Verification

After Task 10, before any merge:

- [ ] `swift test` from `LifeOSKit/` passes in full.
- [ ] `xcodebuild -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds.
- [ ] `grep -rn "MetricsDigest.from" LIfeOS/ LifeOSKit/` shows no remaining single-argument call.
- [ ] `git log --oneline origin/main..HEAD` shows one commit per task, no commit on `main`.
- [ ] Re-read `origin/main` before pushing; peer sessions move it.

## Follow-on, explicitly not in this plan

The cloud tier (`RemoteEngine`, the coach Edge Function, the spend ceiling) stays in `2026-08-25-coach-llm-routing-design.md`. Task 7 does not leave that seam ready. `MetricsDigest.Audience.offDevice` exists and omits the four raw Whoop series, but nothing selects it: `CoachTask.prompt` has no audience parameter and always renders through `promptLines`, which defaults to `.onDevice`, and `Engine.run` has no audience parameter to pass one down. A remote engine built against the current protocol would call `task.prompt(context)` and receive the on-device render, raw series included, with the redaction never applied. Giving `CoachTask.prompt` an audience parameter, and threading it through `Engine.run`, is a prerequisite of that plan's work, not a detail inside it.
