# Whoop Full Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture everything Whoop's four collections return, archive the raw payloads so a field can be added later without re-fetching, and fill the two source-record models that were built for this and never written to.

**Architecture:** Sync becomes fetch, archive, derive. `WhoopClient` returns neutral samples and paginates properly; every record's raw JSON lands in a new `WhoopRawRecord`; `WhoopDerivation` reads the archive and rolls it up into `DailyMetrics`, `WorkoutRecord` and `SleepRecord`. Deriving from the archive rather than the in-flight response means the archive path runs on every sync and cannot rot.

**Tech Stack:** Swift 6 (strict concurrency), SwiftData, Swift Testing (`import Testing`), SwiftPM local package. No new dependencies.

## Global Constraints

- **No new third-party dependencies.** Foundation and SwiftData only.
- **Every new property on an existing `@Model` MUST be optional.** SwiftData's implicit lightweight migration covers additive-and-optional only. A non-optional addition produces a store that will not open.
- **A missing value and a zero are never the same thing.** `nil` means no reading. Never substitute `0`.
- **Module boundaries:** `DesignSystem` depends on nothing. `Persistence` depends on nothing. `Integrations` depends on `Persistence`. Nothing depends on `Integrations` except the app target.
- **Tests run from the terminal:** `swift test --package-path LifeOSKit`. No simulator, ever. The package builds for macOS specifically to keep this true.
- **No em-dashes in prose or comments.** The repository is mid-pass removing them; use a comma, a colon, or a full stop.
- **Whoop kilojoules to kilocalories: divide by 4.184.** Never 4.2, never 4.0.
- **Unscored records are dropped, not zeroed.** `WhoopDTOs.isScored` already encodes this; keep using it.

---

### Task 1: Widen the recovery, sleep and cycle DTOs

The fixtures in `WhoopWireFormatTests.swift` were captured from a live v2 response and already contain every field this task adds. No API call is needed to verify any of it.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift:23-61` (the `WhoopDTOs` enum)
- Modify: `LifeOSKit/Sources/Integrations/WhoopSamples.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `WhoopRecoverySample` gains `spo2Percentage: Double?`, `skinTempCelsius: Double?`. `WhoopSleepSample` gains `respiratoryRate: Double?`, `efficiencyPercentage: Double?`, `sleepNeedMinutes: Int?`, `lightMinutes: Int?`, `remMinutes: Int?`, `swsMinutes: Int?`, `awakeMinutes: Int?`, `disturbanceCount: Int?`. `WhoopCycleSample` gains `calories: Double?`, `averageHR: Double?`, `maxHR: Double?`.

- [ ] **Step 1: Write the failing tests**

Append to `WhoopWireFormatTests.swift`:

```swift
@Test func recoveryCarriesSpO2AndSkinTemperature() throws {
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.RecoveryRecord>.self, from: Data(recoveryJSON.utf8)
    )
    let score = try #require(page.records.first?.score)
    #expect(score.spo2_percentage == 97.2)
    #expect(score.skin_temp_celsius == 33.1)
}

@Test func sleepCarriesStagesRespirationAndNeed() throws {
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
    )
    let score = try #require(page.records.first?.score)
    #expect(score.respiratory_rate == 14.2)
    #expect(score.sleep_efficiency_percentage == 91)
    #expect(score.sleep_needed?.baseline_milli == 27_000_000)

    let stages = try #require(score.stage_summary)
    #expect(stages.total_light_sleep_time_milli == 10)
    #expect(stages.total_rem_sleep_time_milli == 10)
    #expect(stages.total_slow_wave_sleep_time_milli == 10)
    #expect(stages.disturbance_count == 3)
}

@Test func cycleCarriesEnergyAndHeartRates() throws {
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.CycleRecord>.self, from: Data(cycleJSON.utf8)
    )
    let score = try #require(page.records.first?.score)
    #expect(score.kilojoule == 9000.5)
    #expect(score.average_heart_rate == 70)
    #expect(score.max_heart_rate == 170)
}

/// 9000.5 kJ / 4.184 = 2151.17 kcal. The divisor is exact, not 4.2.
@Test func kilojoulesConvertToKilocalories() throws {
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.CycleRecord>.self, from: Data(cycleJSON.utf8)
    )
    let kilojoule = try #require(page.records.first?.score?.kilojoule)
    #expect(abs(kilojoule / 4.184 - 2151.17) < 0.01)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path LifeOSKit --filter WhoopWireFormatTests`
Expected: FAIL, "value of type 'RecoveryRecord.Score' has no member 'spo2_percentage'"

- [ ] **Step 3: Add the fields to the DTOs**

In `WhoopClient.swift`, replace the three `Score` structs:

```swift
struct RecoveryRecord: Decodable {
    let created_at: Date
    let score_state: String?
    let score: Score?

    struct Score: Decodable {
        let recovery_score: Double?
        let resting_heart_rate: Double?
        let hrv_rmssd_milli: Double?
        let spo2_percentage: Double?
        let skin_temp_celsius: Double?
    }
}

struct SleepRecord: Decodable {
    let id: String?
    let start: Date
    let end: Date
    let nap: Bool?
    let score_state: String?
    let score: Score?

    struct Score: Decodable {
        let sleep_performance_percentage: Double?
        let sleep_efficiency_percentage: Double?
        let respiratory_rate: Double?
        let sleep_needed: Needed?
        let stage_summary: Stages?

        struct Needed: Decodable {
            let baseline_milli: Double?
            let need_from_sleep_debt_milli: Double?
        }

        struct Stages: Decodable {
            let total_in_bed_time_milli: Double?
            let total_awake_time_milli: Double?
            let total_light_sleep_time_milli: Double?
            let total_rem_sleep_time_milli: Double?
            let total_slow_wave_sleep_time_milli: Double?
            let disturbance_count: Int?
        }
    }
}

struct CycleRecord: Decodable {
    let id: Int?
    let start: Date
    let score_state: String?
    let score: Score?

    struct Score: Decodable {
        let strain: Double?
        let kilojoule: Double?
        let average_heart_rate: Double?
        let max_heart_rate: Double?
    }
}
```

- [ ] **Step 4: Widen the sample structs**

Replace the three sample structs in `WhoopSamples.swift`. Every new property is optional, and the memberwise initialisers are explicit and public because a struct's memberwise init is internal by default:

```swift
public struct WhoopRecoverySample: Sendable, Equatable {
    public let date: Date
    public let recoveryPercentage: Double?
    public let restingHeartRate: Double?
    public let hrvMilliseconds: Double?
    public let spo2Percentage: Double?
    public let skinTempCelsius: Double?

    public init(date: Date, recoveryPercentage: Double?, restingHeartRate: Double?,
                hrvMilliseconds: Double?, spo2Percentage: Double? = nil,
                skinTempCelsius: Double? = nil) {
        self.date = date
        self.recoveryPercentage = recoveryPercentage
        self.restingHeartRate = restingHeartRate
        self.hrvMilliseconds = hrvMilliseconds
        self.spo2Percentage = spo2Percentage
        self.skinTempCelsius = skinTempCelsius
    }
}

public struct WhoopSleepSample: Sendable, Equatable {
    public let externalID: String?
    public let start: Date
    public let end: Date
    public let isNap: Bool
    public let performancePercentage: Double?
    public let efficiencyPercentage: Double?
    public let respiratoryRate: Double?
    public let sleepNeedMinutes: Int?
    /// Time actually asleep, which is not time in bed.
    public let asleepMinutes: Int?
    public let lightMinutes: Int?
    public let remMinutes: Int?
    public let swsMinutes: Int?
    public let awakeMinutes: Int?
    public let disturbanceCount: Int?

    public init(externalID: String? = nil, start: Date, end: Date, isNap: Bool = false,
                performancePercentage: Double?, efficiencyPercentage: Double? = nil,
                respiratoryRate: Double? = nil, sleepNeedMinutes: Int? = nil,
                asleepMinutes: Int?, lightMinutes: Int? = nil, remMinutes: Int? = nil,
                swsMinutes: Int? = nil, awakeMinutes: Int? = nil,
                disturbanceCount: Int? = nil) {
        self.externalID = externalID
        self.start = start
        self.end = end
        self.isNap = isNap
        self.performancePercentage = performancePercentage
        self.efficiencyPercentage = efficiencyPercentage
        self.respiratoryRate = respiratoryRate
        self.sleepNeedMinutes = sleepNeedMinutes
        self.asleepMinutes = asleepMinutes
        self.lightMinutes = lightMinutes
        self.remMinutes = remMinutes
        self.swsMinutes = swsMinutes
        self.awakeMinutes = awakeMinutes
        self.disturbanceCount = disturbanceCount
    }
}

public struct WhoopCycleSample: Sendable, Equatable {
    public let date: Date
    public let dayStrain: Double?
    public let calories: Double?
    public let averageHR: Double?
    public let maxHR: Double?

    public init(date: Date, dayStrain: Double?, calories: Double? = nil,
                averageHR: Double? = nil, maxHR: Double? = nil) {
        self.date = date
        self.dayStrain = dayStrain
        self.calories = calories
        self.averageHR = averageHR
        self.maxHR = maxHR
    }
}
```

- [ ] **Step 5: Map the new fields in the client**

In `WhoopClient.swift`, update `recoveries` and `cycles`. `sleeps` is rewritten in Task 2, so map only the fields that do not depend on stage summing here:

```swift
public func recoveries(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopRecoverySample] {
    let page: WhoopDTOs.Page<WhoopDTOs.RecoveryRecord> =
        try await get("recovery", accessToken: accessToken, since: since, until: until)
    return page.records
        .filter { WhoopDTOs.isScored($0.score_state) }
        .map {
            WhoopRecoverySample(
                date: $0.created_at,
                recoveryPercentage: $0.score?.recovery_score,
                restingHeartRate: $0.score?.resting_heart_rate,
                hrvMilliseconds: $0.score?.hrv_rmssd_milli,
                spo2Percentage: $0.score?.spo2_percentage,
                skinTempCelsius: $0.score?.skin_temp_celsius
            )
        }
}

public func cycles(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopCycleSample] {
    let page: WhoopDTOs.Page<WhoopDTOs.CycleRecord> =
        try await get("cycle", accessToken: accessToken, since: since, until: until)
    return page.records
        .filter { WhoopDTOs.isScored($0.score_state) }
        .map {
            WhoopCycleSample(
                date: $0.start,
                dayStrain: $0.score?.strain,
                // Kilojoules to kilocalories. The divisor is exact.
                calories: $0.score?.kilojoule.map { $0 / 4.184 },
                averageHR: $0.score?.average_heart_rate,
                maxHR: $0.score?.max_heart_rate
            )
        }
}
```

`get` still returns `Page<Record>` at this point and the call sites unwrap `.records`. Task 4 changes it to return `[Record]` across every page and removes the unwrapping. Do not anticipate that change here: writing `let records: [X] = try await get(...)` against the current `get` compiles and then fails at runtime, because the generic would try to decode a bare array from a paged envelope.

- [ ] **Step 6: Correct the stale header comment**

Replace lines 3-9 of `WhoopClient.swift`:

```swift
/// Wire shapes for the Whoop developer API.
///
/// Recovery, sleep and cycle are fixture-backed: `WhoopWireFormatTests` holds
/// payloads captured from a live v2 response, so a decode failure in those three
/// means the API moved, not that the app was guessed wrong. Workout is the one
/// collection with no captured fixture yet.
```

- [ ] **Step 7: Run the full suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, 67 tests

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopClient.swift \
        LifeOSKit/Sources/Integrations/WhoopSamples.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift
git commit -m "feat(whoop): read the recovery, sleep and cycle fields we were discarding"
```

---

### Task 2: Sum sleep stages instead of subtracting awake time

`asleepMinutes` is currently `in_bed - awake`, a proxy for `light + SWS + REM` that drifts whenever Whoop counts time as neither.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift` (the `sleeps` function)
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift`

**Interfaces:**
- Consumes: `WhoopSleepSample` from Task 1.
- Produces: no signature change. `sleeps` now returns naps as well, flagged by `isNap`.

- [ ] **Step 1: Write the failing tests**

Replace the existing `sleepAsleepTimeIsInBedMinusAwake` test with these:

```swift
/// light + SWS + REM is the direct measure. The fixture's stages are 10ms each,
/// so the sum is 30ms, which floors to 0 minutes, while in_bed - awake would
/// give 400. The two disagreeing is the whole point of the change.
@Test func asleepTimeSumsTheStagesWhenTheyArePresent() throws {
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(sleepJSON.utf8)
    )
    let record = try #require(page.records.first)
    #expect(WhoopSleepMath.asleepMinutes(from: record.score?.stage_summary) == 0)
}

@Test func asleepTimeFallsBackToInBedMinusAwakeWhenStagesAreMissing() {
    let stages = WhoopDTOs.SleepRecord.Score.Stages(
        total_in_bed_time_milli: 25_200_000,
        total_awake_time_milli: 1_200_000,
        total_light_sleep_time_milli: nil,
        total_rem_sleep_time_milli: nil,
        total_slow_wave_sleep_time_milli: nil,
        disturbance_count: nil
    )
    #expect(WhoopSleepMath.asleepMinutes(from: stages) == 400)
}

@Test func asleepTimeIsNilWhenThereIsNothingToComputeFrom() {
    #expect(WhoopSleepMath.asleepMinutes(from: nil) == nil)
}

/// A nap is not the night's sleep and must not overwrite it, but it is still a
/// real record and is no longer thrown away.
@Test func napsAreReturnedAndFlagged() throws {
    let json = #"{"records":[{"id":"nap-1","start":"2026-08-10T14:00:00Z","end":"2026-08-10T14:30:00Z","nap":true,"score_state":"SCORED","score":null}],"next_token":null}"#
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.SleepRecord>.self, from: Data(json.utf8)
    )
    #expect(page.records.first?.nap == true)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WhoopWireFormatTests`
Expected: FAIL, "cannot find 'WhoopSleepMath' in scope"

- [ ] **Step 3: Add the pure helper**

Create `LifeOSKit/Sources/Integrations/WhoopSleepMath.swift`:

```swift
import Foundation

/// Sleep arithmetic, kept separate from the client so it is testable without a
/// network layer and reviewable on its own.
enum WhoopSleepMath {
    /// Time actually asleep, in minutes.
    ///
    /// Prefers summing the stages, which is the direct measure. Falls back to
    /// time in bed minus time awake when the stage breakdown is absent, so a
    /// partial payload degrades rather than nulling the field.
    static func asleepMinutes(from stages: WhoopDTOs.SleepRecord.Score.Stages?) -> Int? {
        guard let stages else { return nil }

        let light = stages.total_light_sleep_time_milli
        let rem = stages.total_rem_sleep_time_milli
        let sws = stages.total_slow_wave_sleep_time_milli

        if light != nil || rem != nil || sws != nil {
            let total = (light ?? 0) + (rem ?? 0) + (sws ?? 0)
            return Int(total / 60_000)
        }

        guard let inBed = stages.total_in_bed_time_milli else { return nil }
        let awake = stages.total_awake_time_milli ?? 0
        return Int(max(inBed - awake, 0) / 60_000)
    }

    static func minutes(fromMilliseconds milli: Double?) -> Int? {
        milli.map { Int($0 / 60_000) }
    }
}
```

- [ ] **Step 4: Rewrite the sleeps mapping**

In `WhoopClient.swift`:

```swift
public func sleeps(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopSleepSample] {
    let page: WhoopDTOs.Page<WhoopDTOs.SleepRecord> =
        try await get("activity/sleep", accessToken: accessToken, since: since, until: until)
    return page.records
        .filter { WhoopDTOs.isScored($0.score_state) }
        .map { record in
            let stages = record.score?.stage_summary
            let need = record.score?.sleep_needed
            return WhoopSleepSample(
                externalID: record.id,
                start: record.start,
                end: record.end,
                // Naps are returned rather than filtered out. The derivation
                // layer decides what a nap may write; dropping them here meant
                // a real record vanished with no trace.
                isNap: record.nap == true,
                performancePercentage: record.score?.sleep_performance_percentage,
                efficiencyPercentage: record.score?.sleep_efficiency_percentage,
                respiratoryRate: record.score?.respiratory_rate,
                sleepNeedMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.baseline_milli),
                asleepMinutes: WhoopSleepMath.asleepMinutes(from: stages),
                lightMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_light_sleep_time_milli),
                remMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_rem_sleep_time_milli),
                swsMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_slow_wave_sleep_time_milli),
                awakeMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_awake_time_milli),
                disturbanceCount: stages?.disturbance_count
            )
        }
}
```

- [ ] **Step 5: Run the suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopSleepMath.swift \
        LifeOSKit/Sources/Integrations/WhoopClient.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift
git commit -m "fix(whoop): measure sleep by summing stages, not by subtracting awake time"
```

---

### Task 3: The raw archive

**Files:**
- Create: `LifeOSKit/Sources/Persistence/WhoopRawRecord.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift:5-14`
- Test: `LifeOSKit/Tests/PersistenceTests/WhoopArchiveTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `WhoopRawRecord` model, and `WhoopArchive` with `store(kind:externalID:payload:) throws`, `payloads(kind: String) throws -> [Data]`, `count() throws -> Int`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/WhoopArchiveTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct WhoopArchiveTests {
    private func makeArchive() throws -> WhoopArchive {
        let container = try LifeOSContainer.make(inMemory: true)
        return WhoopArchive(context: ModelContext(container))
    }

    @Test func storingAPayloadMakesItReadableBack() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data(#"{"a":1}"#.utf8))

        let payloads = try archive.payloads(kind: "recovery")
        #expect(payloads.count == 1)
        #expect(String(decoding: payloads[0], as: UTF8.self) == #"{"a":1}"#)
    }

    /// A re-sync sees the same records again. Storing them must correct the row
    /// rather than pile up a duplicate for every sync the user ever runs.
    @Test func restoringTheSameRecordUpdatesRatherThanDuplicating() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data(#"{"v":1}"#.utf8))
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data(#"{"v":2}"#.utf8))

        let payloads = try archive.payloads(kind: "recovery")
        #expect(payloads.count == 1)
        #expect(String(decoding: payloads[0], as: UTF8.self) == #"{"v":2}"#)
    }

    /// The same external id in two collections is two different records.
    @Test func kindIsPartOfIdentity() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "1", payload: Data("r".utf8))
        try archive.store(kind: "cycle", externalID: "1", payload: Data("c".utf8))

        #expect(try archive.payloads(kind: "recovery").count == 1)
        #expect(try archive.payloads(kind: "cycle").count == 1)
        #expect(try archive.count() == 2)
    }

    @Test func readingAnEmptyKindReturnsNothingRatherThanFailing() throws {
        let archive = try makeArchive()
        #expect(try archive.payloads(kind: "workout").isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WhoopArchiveTests`
Expected: FAIL, "cannot find 'WhoopArchive' in scope"

- [ ] **Step 3: Create the model and archive**

Create `LifeOSKit/Sources/Persistence/WhoopRawRecord.swift`:

```swift
import Foundation
import SwiftData

/// An unprocessed Whoop payload, retained so re-derivation never requires
/// re-fetching. Whoop rate-limits, and a derivation bug found six months from
/// now must be fixable without asking for the data again.
///
/// The columns mirror the `whoop_raw` table in the Supabase schema so moving
/// this server-side later is a copy rather than a redesign.
@Model
public final class WhoopRawRecord {
    #Unique<WhoopRawRecord>([\.kind, \.externalID])

    /// Whoop's collection name: recovery, sleep, cycle or workout. A String and
    /// not an enum, so a collection we have never seen lands as data rather
    /// than as a failed insert.
    public var kind: String
    public var externalID: String
    public var payload: Data
    public var receivedAt: Date

    public init(kind: String, externalID: String, payload: Data, receivedAt: Date = .now) {
        self.kind = kind
        self.externalID = externalID
        self.payload = payload
        self.receivedAt = receivedAt
    }
}

/// Reads and writes the raw archive. Upserts on (kind, externalID) because a
/// re-sync returns records already seen.
@MainActor
public struct WhoopArchive {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func store(kind: String, externalID: String, payload: Data) throws {
        let existing = try context.fetch(
            FetchDescriptor<WhoopRawRecord>(
                predicate: #Predicate { $0.kind == kind && $0.externalID == externalID }
            )
        ).first

        if let existing {
            existing.payload = payload
            existing.receivedAt = .now
        } else {
            context.insert(WhoopRawRecord(kind: kind, externalID: externalID, payload: payload))
        }
        try context.save()
    }

    /// Batched: one save for a whole page, because a save per record turns a
    /// fourteen-day sync into hundreds of writes.
    public func store(_ records: [(kind: String, externalID: String, payload: Data)]) throws {
        for record in records {
            let kind = record.kind
            let id = record.externalID
            let existing = try context.fetch(
                FetchDescriptor<WhoopRawRecord>(
                    predicate: #Predicate { $0.kind == kind && $0.externalID == id }
                )
            ).first

            if let existing {
                existing.payload = record.payload
                existing.receivedAt = .now
            } else {
                context.insert(WhoopRawRecord(kind: kind, externalID: id, payload: record.payload))
            }
        }
        try context.save()
    }

    public func payloads(kind: String) throws -> [Data] {
        try context.fetch(
            FetchDescriptor<WhoopRawRecord>(
                predicate: #Predicate { $0.kind == kind },
                sortBy: [SortDescriptor(\.receivedAt)]
            )
        ).map(\.payload)
    }

    public func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<WhoopRawRecord>())
    }
}
```

- [ ] **Step 4: Register the model**

In `LifeOSContainer.swift`, add `WhoopRawRecord.self` to the schema array:

```swift
public static let schema = Schema([
    DailyMetrics.self,
    UserGoals.self,
    WorkoutRecord.self,
    SleepRecord.self,
    WhoopRawRecord.self,
    PlanEntry.self,
    HabitTick.self,
    MoneyEntry.self,
    MoneyAccount.self,
])
```

- [ ] **Step 5: Run the suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/WhoopRawRecord.swift \
        LifeOSKit/Sources/Persistence/LifeOSContainer.swift \
        LifeOSKit/Tests/PersistenceTests/WhoopArchiveTests.swift
git commit -m "feat(whoop): archive raw payloads so re-derivation never re-fetches"
```

---

### Task 4: Follow pagination

`Page.next_token` is decoded and discarded while `get` sends `limit=25`. Fourteen days of daily records fit under 25, so this is invisible today and breaks the moment workouts arrive.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift` (the `get` function and its three call sites)
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopPaginationTests.swift`

**Interfaces:**
- Consumes: the DTOs from Task 1.
- Produces: `get` changes signature from `get<T: Decodable>(...) async throws -> T` to `get<Record: Decodable>(...) async throws -> [Record]`, returning every record across every page. Call sites stop unwrapping `.records`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/WhoopPaginationTests.swift`:

```swift
import Testing
import Foundation
@testable import Integrations

/// Serves canned pages so pagination is testable without a network or a token.
final class StubURLProtocol: URLProtocol {
    /// Bodies served in order, one per request.
    nonisolated(unsafe) static var bodies: [String] = []
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        let body = Self.bodies.isEmpty ? #"{"records":[],"next_token":null}"# : Self.bodies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct WhoopPaginationTests {
    private func makeClient() -> WhoopClient {
        StubURLProtocol.bodies = []
        StubURLProtocol.requestedURLs = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return WhoopClient(session: URLSession(configuration: configuration))
    }

    private func cyclePage(id: Int, next: String?) -> String {
        let token = next.map { "\"\($0)\"" } ?? "null"
        return """
        {"records":[{"id":\(id),"start":"2026-08-10T10:00:00Z","score_state":"SCORED",
          "score":{"strain":1.0,"kilojoule":100,"average_heart_rate":60,"max_heart_rate":100}}],
         "next_token":\(token)}
        """
    }

    @Test func everyPageIsFollowedUntilTheTokenIsNil() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = [
            cyclePage(id: 1, next: "t1"),
            cyclePage(id: 2, next: "t2"),
            cyclePage(id: 3, next: nil),
        ]

        let samples = try await client.cycles(accessToken: "x", since: .now, until: .now)
        #expect(samples.count == 3)
        #expect(StubURLProtocol.requestedURLs.count == 3)
    }

    @Test func theFollowUpRequestCarriesTheNextToken() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = [cyclePage(id: 1, next: "abc"), cyclePage(id: 2, next: nil)]

        _ = try await client.cycles(accessToken: "x", since: .now, until: .now)
        let second = try #require(StubURLProtocol.requestedURLs.last?.absoluteString)
        #expect(second.contains("nextToken=abc"))
    }

    @Test func aSinglePageMakesOneRequest() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = [cyclePage(id: 1, next: nil)]

        let samples = try await client.cycles(accessToken: "x", since: .now, until: .now)
        #expect(samples.count == 1)
        #expect(StubURLProtocol.requestedURLs.count == 1)
    }

    /// A server that always returns a token must not spin forever.
    @Test func thePageCapBoundsARunawayResponse() async throws {
        let client = makeClient()
        StubURLProtocol.bodies = (0..<40).map { cyclePage(id: $0, next: "always") }

        let samples = try await client.cycles(accessToken: "x", since: .now, until: .now)
        #expect(StubURLProtocol.requestedURLs.count == 20)
        #expect(samples.count == 20)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WhoopPaginationTests`
Expected: FAIL, only one request made and one sample returned

- [ ] **Step 3: Rewrite `get` as a paging loop**

In `WhoopClient.swift`, replace `get` entirely:

```swift
/// Whoop returns at most `limit` records per page and a `next_token` for the
/// rest. The token used to be decoded and dropped, which was invisible while
/// only daily records were fetched, twenty five being more than fourteen days
/// of them. Workouts do not fit, and a silent partial sync reads exactly like a
/// quiet fortnight.
private static let pageLimit = 25
/// Bounds a server that keeps handing back a token. Hitting this is logged,
/// because a silent truncation reads as a complete sync.
private static let pageCap = 20

private func get<Record: Decodable>(
    _ path: String, accessToken: String, since: Date, until: Date
) async throws -> [Record] {
    var all: [Record] = []
    var nextToken: String?
    var pages = 0

    repeat {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        let formatter = ISO8601DateFormatter()
        var items = [
            URLQueryItem(name: "start", value: formatter.string(from: since)),
            URLQueryItem(name: "end", value: formatter.string(from: until)),
            URLQueryItem(name: "limit", value: String(Self.pageLimit)),
        ]
        if let nextToken { items.append(URLQueryItem(name: "nextToken", value: nextToken)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhoopAPIError.transport }

        switch http.statusCode {
        case 200..<300: break
        case 401: throw WhoopAPIError.unauthorized      // caller refreshes and retries
        case 429: throw WhoopAPIError.rateLimited
        default:  throw WhoopAPIError.status(http.statusCode)
        }

        let page: WhoopDTOs.Page<Record>
        do {
            page = try WhoopClient.decoder.decode(WhoopDTOs.Page<Record>.self, from: data)
        } catch {
            // Distinguished from a transport failure so a field-name drift is
            // obvious rather than looking like a network problem.
            throw WhoopAPIError.decoding(String(describing: error))
        }

        all.append(contentsOf: page.records)
        nextToken = page.next_token
        pages += 1

        if pages >= Self.pageCap, nextToken != nil {
            whoopClientLog.error(
                "\(path, privacy: .public): stopped at the \(Self.pageCap, privacy: .public) page cap with a token still pending; the sync is partial"
            )
            break
        }
    } while nextToken != nil

    return all
}
```

Add the logger at the top of the file, below the imports:

```swift
import OSLog

private let whoopClientLog = Logger(subsystem: "shivvyas.LIfeOS", category: "whoop-client")
```

- [ ] **Step 4: Drop the `.records` unwrapping at the three call sites**

Each of `recoveries`, `sleeps` and `cycles` currently binds a `Page` and reads `page.records`. Change all three to bind the array directly, which is what the new `get` returns:

```swift
// recoveries
let records: [WhoopDTOs.RecoveryRecord] =
    try await get("recovery", accessToken: accessToken, since: since, until: until)
return records
    .filter { WhoopDTOs.isScored($0.score_state) }
    // ...unchanged mapping...

// sleeps
let records: [WhoopDTOs.SleepRecord] =
    try await get("activity/sleep", accessToken: accessToken, since: since, until: until)
return records
    .filter { WhoopDTOs.isScored($0.score_state) }
    // ...unchanged mapping...

// cycles
let records: [WhoopDTOs.CycleRecord] =
    try await get("cycle", accessToken: accessToken, since: since, until: until)
return records
    .filter { WhoopDTOs.isScored($0.score_state) }
    // ...unchanged mapping...
```

`WhoopDTOs.Page` stays: `get` still decodes into it internally to read `next_token`.

- [ ] **Step 5: Run the suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopClient.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopPaginationTests.swift
git commit -m "fix(whoop): follow pagination instead of keeping only the first page"
```

---

### Task 5: Widen the persistence models

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/DailyMetrics.swift:16-30`
- Modify: `LifeOSKit/Sources/Persistence/SourceRecords.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/WhoopArchiveTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `DailyMetrics` gains `spo2Percentage: Double?`, `skinTempCelsius: Double?`, `respiratoryRate: Double?`, `whoopCalories: Double?`. `SleepRecord` gains `performancePercentage: Double?`, `lightMinutes: Int?`, `remMinutes: Int?`, `swsMinutes: Int?`, `awakeMinutes: Int?`, `respiratoryRate: Double?`, `sleepNeedMinutes: Int?`, `disturbanceCount: Int?`, `isNap: Bool?`. `WorkoutRecord` gains `strain: Double?`, `averageHR: Double?`, `maxHR: Double?`, `distanceMeters: Double?`.

- [ ] **Step 1: Write the failing test**

Append to `WhoopArchiveTests.swift`:

```swift
/// Every added property must be optional. SwiftData's implicit lightweight
/// migration covers additive-and-optional only, and a non-optional addition
/// produces a store that will not open on an existing install.
@Suite @MainActor struct WidenedModelTests {
    @Test func theContainerStillOpensWithTheWidenedSchema() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        // The `try` above is the real assertion: a non-optional addition makes
        // the store fail to open. This names the entity so the test also fails
        // if the model is dropped from the schema rather than merely widened.
        let names = container.schema.entities.map(\.name)
        #expect(names.contains("WhoopRawRecord"))
        #expect(names.contains("DailyMetrics"))
    }

    @Test func newDailyMetricsFieldsDefaultToNilRatherThanZero() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MetricsStore(context: ModelContext(container))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

        try store.upsert(date: day) { $0.steps = 100 }
        let row = try #require(try store.metrics(from: day, to: day).first)

        #expect(row.spo2Percentage == nil)
        #expect(row.skinTempCelsius == nil)
        #expect(row.respiratoryRate == nil)
        #expect(row.whoopCalories == nil)
    }

    @Test func sleepRecordCarriesItsStages() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let record = SleepRecord(externalID: "s-1", start: .now, end: .now.addingTimeInterval(3600),
                                 attributedDate: Calendar.current.startOfDay(for: .now))
        record.lightMinutes = 200
        record.remMinutes = 90
        record.swsMinutes = 80
        context.insert(record)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<SleepRecord>()).first)
        #expect(stored.lightMinutes == 200)
        #expect(stored.remMinutes == 90)
        #expect(stored.swsMinutes == 80)
        #expect(stored.respiratoryRate == nil)
    }

    @Test func workoutRecordCarriesStrainAndHeartRates() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let workout = WorkoutRecord(externalID: "w-1", start: .now, durationMinutes: 45,
                                    activityName: "Running", energyKcal: 500)
        workout.strain = 12.4
        workout.averageHR = 145
        workout.maxHR = 178
        context.insert(workout)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<WorkoutRecord>()).first)
        #expect(stored.strain == 12.4)
        #expect(stored.averageHR == 145)
        #expect(stored.distanceMeters == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WidenedModelTests`
Expected: FAIL, "value of type 'DailyMetrics' has no member 'spo2Percentage'"

- [ ] **Step 3: Widen `DailyMetrics`**

In `DailyMetrics.swift`, add below `whoopSleepPerformancePct`:

```swift
    public var whoopRecoveryPct: Double?
    public var whoopDayStrain: Double?
    public var whoopSleepPerformancePct: Double?

    /// Daily scalars worth rendering. Everything else Whoop returns lives in
    /// the raw archive, where adding a column later costs a re-derive and no
    /// network traffic at all.
    public var spo2Percentage: Double?
    public var skinTempCelsius: Double?
    public var respiratoryRate: Double?
    public var whoopCalories: Double?
```

- [ ] **Step 4: Widen the source records**

In `SourceRecords.swift`, add these properties inside `WorkoutRecord`, after `energyKcal`:

```swift
    public var strain: Double?
    public var averageHR: Double?
    public var maxHR: Double?
    public var distanceMeters: Double?
```

And inside `SleepRecord`, after `attributedDate`:

```swift
    public var performancePercentage: Double?
    public var lightMinutes: Int?
    public var remMinutes: Int?
    public var swsMinutes: Int?
    public var awakeMinutes: Int?
    public var respiratoryRate: Double?
    public var sleepNeedMinutes: Int?
    public var disturbanceCount: Int?
    /// Optional rather than a defaulted Bool, because a non-optional addition
    /// is what turns a lightweight migration into a store that will not open.
    public var isNap: Bool?
```

Leave both initialisers untouched. New properties are set after construction, which is exactly what keeps them optional and the migration lightweight.

- [ ] **Step 5: Run the suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/DailyMetrics.swift \
        LifeOSKit/Sources/Persistence/SourceRecords.swift \
        LifeOSKit/Tests/PersistenceTests/WhoopArchiveTests.swift
git commit -m "feat(whoop): widen the daily spine and source records for the new readings"
```

---

### Task 6: `WhoopDerivation` replaces `WhoopIngestion`

**Files:**
- Create: `LifeOSKit/Sources/Integrations/WhoopDerivation.swift`
- Delete: `LifeOSKit/Sources/Integrations/WhoopIngestion.swift`
- Modify: `LifeOSKit/Sources/Integrations/WhoopSync.swift:60-112`
- Modify: `LIfeOS/Features/Settings/ViewModel/WhoopConnectionViewModel.swift:245-249`
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopTests.swift` (the `WhoopIngestionTests` suite)

**Interfaces:**
- Consumes: `WhoopArchive` (Task 3), the widened samples (Tasks 1, 2), the widened models (Task 5).
- Produces: `WhoopDerivation(store: MetricsStore, archive: WhoopArchive, calendar: Calendar = .current)` with `derive(recoveries:sleeps:cycles:) throws` and `rederive() throws -> Int` returning the number of days rewritten.

- [ ] **Step 1: Write the failing tests**

In `WhoopTests.swift`, rename the `WhoopIngestionTests` suite to `WhoopDerivationTests`, replace `WhoopIngestion(store:)` with `WhoopDerivation(store:archive:)` throughout, and append:

```swift
@Test func spo2SkinTempAndCaloriesReachTheRow() throws {
    let container = try LifeOSContainer.make(inMemory: true)
    let context = ModelContext(container)
    let store = MetricsStore(context: context)
    let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))

    let day = date(2026, 8, 10)
    try derivation.derive(
        recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 66,
                                         restingHeartRate: 54, hrvMilliseconds: 74.5,
                                         spo2Percentage: 97.2, skinTempCelsius: 33.1)],
        sleeps: [],
        cycles: [WhoopCycleSample(date: day, dayStrain: 12.7, calories: 2151.6,
                                  averageHR: 70, maxHR: 170)]
    )

    let row = try #require(try store.metrics(from: day, to: day).first)
    #expect(row.spo2Percentage == 97.2)
    #expect(row.skinTempCelsius == 33.1)
    #expect(row.whoopCalories == 2151.6)
}

/// A nap must not overwrite the night's sleep on the daily row, but it is still
/// stored as a record of its own rather than dropped.
@Test func aNapIsStoredButDoesNotTouchTheDayRow() throws {
    let container = try LifeOSContainer.make(inMemory: true)
    let context = ModelContext(container)
    let store = MetricsStore(context: context)
    let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))

    let day = date(2026, 8, 10)
    try derivation.derive(
        recoveries: [],
        sleeps: [
            WhoopSleepSample(externalID: "night", start: date(2026, 8, 9, 23),
                             end: date(2026, 8, 10, 7), isNap: false,
                             performancePercentage: 88, asleepMinutes: 420),
            WhoopSleepSample(externalID: "nap", start: date(2026, 8, 10, 14),
                             end: date(2026, 8, 10, 14), isNap: true,
                             performancePercentage: nil, asleepMinutes: 30),
        ],
        cycles: []
    )

    let row = try #require(try store.metrics(from: day, to: day).first)
    #expect(row.sleepMinutes == 420)        // the night, not the nap, not the sum

    let records = try context.fetch(FetchDescriptor<SleepRecord>())
    #expect(records.count == 2)             // both stored
    #expect(records.contains { $0.isNap == true })
}

/// The whole point of the archive: rebuild the metrics from stored payloads
/// with no network call.
@Test func rederiveRebuildsTheRowsFromTheArchiveAlone() throws {
    let container = try LifeOSContainer.make(inMemory: true)
    let context = ModelContext(container)
    let store = MetricsStore(context: context)
    let archive = WhoopArchive(context: context)
    let derivation = WhoopDerivation(store: store, archive: archive)

    try archive.store(kind: "recovery", externalID: "r-1", payload: Data("""
    {"created_at":"2026-08-10T13:37:33.957Z","score_state":"SCORED",
     "score":{"recovery_score":66,"resting_heart_rate":54,"hrv_rmssd_milli":74.5,
              "spo2_percentage":97.2,"skin_temp_celsius":33.1}}
    """.utf8))

    let days = try derivation.rederive()
    #expect(days == 1)

    let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_786_282_653))
    let rows = try store.metrics(from: day.addingTimeInterval(-86_400 * 2),
                                 to: day.addingTimeInterval(86_400 * 2))
    #expect(rows.contains { $0.whoopRecoveryPct == 66 })
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WhoopDerivationTests`
Expected: FAIL, "cannot find 'WhoopDerivation' in scope"

- [ ] **Step 3: Create `WhoopDerivation`**

Create `LifeOSKit/Sources/Integrations/WhoopDerivation.swift`:

```swift
import Foundation
import SwiftData
import Persistence

/// Rolls Whoop readings into the daily spine and the source records.
///
/// Replaces `WhoopIngestion` and keeps its two load-bearing properties: every
/// write goes through `MetricsStore.upsertBatch`, so a re-sync merges into the
/// existing row rather than replacing it, and a nil field never overwrites a
/// stored value. HealthKit owns steps and weight on the same row and must not
/// be clobbered.
@MainActor
public struct WhoopDerivation {
    private let store: MetricsStore
    private let archive: WhoopArchive
    private let calendar: Calendar

    public init(store: MetricsStore, archive: WhoopArchive, calendar: Calendar = .current) {
        self.store = store
        self.archive = archive
        self.calendar = calendar
    }

    public func derive(
        recoveries: [WhoopRecoverySample] = [],
        sleeps: [WhoopSleepSample] = [],
        cycles: [WhoopCycleSample] = []
    ) throws {
        try storeSleepRecords(sleeps)

        // Index by day first so one day touched by all three sources is written
        // once, not three times. Naps are excluded here and here only: they are
        // stored above as records, but a nap is not the night and must not
        // overwrite it.
        var byDay: [Date: (WhoopRecoverySample?, WhoopSleepSample?, WhoopCycleSample?)] = [:]

        for sample in recoveries {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day, default: (nil, nil, nil)].0 = sample
        }
        for sample in sleeps where !sample.isNap {
            let day = WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar)
            byDay[day, default: (nil, nil, nil)].1 = sample
        }
        for sample in cycles {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day, default: (nil, nil, nil)].2 = sample
        }

        guard !byDay.isEmpty else { return }

        try store.upsertBatch(dates: Array(byDay.keys)) { date, row in
            let day = calendar.startOfDay(for: date)
            guard let (recovery, sleep, cycle) = byDay[day] else { return }

            // Nil never overwrites a stored value: a sample that omits a field
            // means "no reading", not "clear what you had".
            if let value = recovery?.recoveryPercentage { row.whoopRecoveryPct = value }
            if let value = recovery?.restingHeartRate { row.restingHR = value }
            if let value = recovery?.hrvMilliseconds { row.hrvMs = value }
            if let value = recovery?.spo2Percentage { row.spo2Percentage = value }
            if let value = recovery?.skinTempCelsius { row.skinTempCelsius = value }

            if let value = sleep?.performancePercentage { row.whoopSleepPerformancePct = value }
            if let value = sleep?.asleepMinutes { row.sleepMinutes = value }
            if let value = sleep?.respiratoryRate { row.respiratoryRate = value }

            if let value = cycle?.dayStrain { row.whoopDayStrain = value }
            if let value = cycle?.calories { row.whoopCalories = value }

            row.syncedAt = .now
        }
    }

    /// Rebuilds every metric row from the archive, with no network call. This is
    /// the capability the archive exists for: a derivation bug found months from
    /// now is fixable without asking Whoop for the data again.
    @discardableResult
    public func rederive() throws -> Int {
        let recoveries = try decode(kind: "recovery", as: WhoopDTOs.RecoveryRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map {
                WhoopRecoverySample(
                    date: $0.created_at,
                    recoveryPercentage: $0.score?.recovery_score,
                    restingHeartRate: $0.score?.resting_heart_rate,
                    hrvMilliseconds: $0.score?.hrv_rmssd_milli,
                    spo2Percentage: $0.score?.spo2_percentage,
                    skinTempCelsius: $0.score?.skin_temp_celsius
                )
            }

        let cycles = try decode(kind: "cycle", as: WhoopDTOs.CycleRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map {
                WhoopCycleSample(
                    date: $0.start,
                    dayStrain: $0.score?.strain,
                    calories: $0.score?.kilojoule.map { $0 / 4.184 },
                    averageHR: $0.score?.average_heart_rate,
                    maxHR: $0.score?.max_heart_rate
                )
            }

        let sleeps = try decode(kind: "sleep", as: WhoopDTOs.SleepRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map { record -> WhoopSleepSample in
                let stages = record.score?.stage_summary
                let need = record.score?.sleep_needed
                return WhoopSleepSample(
                    externalID: record.id,
                    start: record.start,
                    end: record.end,
                    isNap: record.nap == true,
                    performancePercentage: record.score?.sleep_performance_percentage,
                    efficiencyPercentage: record.score?.sleep_efficiency_percentage,
                    respiratoryRate: record.score?.respiratory_rate,
                    sleepNeedMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.baseline_milli),
                    asleepMinutes: WhoopSleepMath.asleepMinutes(from: stages),
                    lightMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_light_sleep_time_milli),
                    remMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_rem_sleep_time_milli),
                    swsMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_slow_wave_sleep_time_milli),
                    awakeMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_awake_time_milli),
                    disturbanceCount: stages?.disturbance_count
                )
            }

        try derive(recoveries: recoveries, sleeps: sleeps, cycles: cycles)

        var days = Set<Date>()
        for sample in recoveries { days.insert(calendar.startOfDay(for: sample.date)) }
        for sample in cycles { days.insert(calendar.startOfDay(for: sample.date)) }
        for sample in sleeps where !sample.isNap {
            days.insert(WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar))
        }
        return days.count
    }

    private func decode<Record: Decodable>(kind: String, as: Record.Type) throws -> [Record] {
        try archive.payloads(kind: kind).compactMap {
            // A single unreadable payload must not fail the whole re-derivation.
            try? WhoopClient.decoder.decode(Record.self, from: $0)
        }
    }

    private func storeSleepRecords(_ sleeps: [WhoopSleepSample]) throws {
        for sample in sleeps {
            guard let externalID = sample.externalID else { continue }
            try store.upsertSleepRecord(
                externalID: externalID,
                start: sample.start,
                end: sample.end,
                attributedDate: WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar)
            ) { record in
                record.performancePercentage = sample.performancePercentage
                record.lightMinutes = sample.lightMinutes
                record.remMinutes = sample.remMinutes
                record.swsMinutes = sample.swsMinutes
                record.awakeMinutes = sample.awakeMinutes
                record.respiratoryRate = sample.respiratoryRate
                record.sleepNeedMinutes = sample.sleepNeedMinutes
                record.disturbanceCount = sample.disturbanceCount
                record.isNap = sample.isNap
            }
        }
    }
}
```

- [ ] **Step 4: Add the sleep-record upsert to `MetricsStore`**

Append to `LifeOSKit/Sources/Persistence/MetricsStore.swift`, inside the `MetricsStore` struct:

```swift
    /// Upsert keyed on the provider's record id, so a re-sync corrects a record
    /// rather than adding a second copy of the same night.
    public func upsertSleepRecord(
        externalID: String,
        start: Date,
        end: Date,
        attributedDate: Date,
        apply: (SleepRecord) -> Void
    ) throws {
        let existing = try context.fetch(
            FetchDescriptor<SleepRecord>(predicate: #Predicate { $0.externalID == externalID })
        ).first

        let record = existing ?? SleepRecord(
            externalID: externalID, start: start, end: end, attributedDate: attributedDate
        )
        if existing == nil { context.insert(record) }
        record.start = start
        record.end = end
        record.attributedDate = attributedDate
        apply(record)
        try context.save()
    }
```

- [ ] **Step 5: Delete `WhoopIngestion` and update its two call sites**

```bash
git rm LifeOSKit/Sources/Integrations/WhoopIngestion.swift
```

In `WhoopSync.swift`, change the stored property, the initialiser parameter and the `sync` body from `WhoopIngestion` to `WhoopDerivation`, and rename `ingestion` to `derivation`. The call becomes:

```swift
try derivation.derive(recoveries: recoveries, sleeps: sleeps, cycles: cycles)
```

In `WhoopConnectionViewModel.swift:245-249`, update the construction:

```swift
let sync = WhoopSync(
    exchange: WhoopTokenExchange(endpoint: endpoint),
    tokens: tokens,
    derivation: WhoopDerivation(
        store: MetricsStore(context: context),
        archive: WhoopArchive(context: context)
    )
)
```

- [ ] **Step 6: Run the suite and build the app**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build`
Expected: exit 0, no errors

- [ ] **Step 7: Commit**

```bash
git add -A LifeOSKit/Sources/Integrations LifeOSKit/Sources/Persistence/MetricsStore.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopTests.swift \
        LIfeOS/Features/Settings/ViewModel/WhoopConnectionViewModel.swift
git commit -m "feat(whoop): derive from the archive and fill the sleep source records"
```

---

### Task 7: Archive on sync, and capture a workout payload

This task ends at a gate. The workout DTO cannot be written until a real payload has been seen, because `/v2/activity/workout` has never been called and has no fixture.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift`
- Modify: `LifeOSKit/Sources/Integrations/WhoopSync.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopPaginationTests.swift`

**Interfaces:**
- Consumes: `WhoopArchive` (Task 3), the paging `get` (Task 4).
- Produces: `WhoopClient.rawPages(_ path: String, accessToken: String, since: Date, until: Date) async throws -> [Data]`, and `WhoopClient.shouldDumpPayloads(_ environment: [String: String]) -> Bool`.

- [ ] **Step 1: Write the failing test for the dump gate**

Append to `WhoopPaginationTests.swift`:

```swift
@Suite struct WhoopDumpGateTests {
    @Test func dumpingIsOffByDefault() {
        #expect(WhoopClient.shouldDumpPayloads([:]) == false)
    }

    @Test func dumpingIsOnOnlyForAnExplicitOne() {
        #expect(WhoopClient.shouldDumpPayloads(["WHOOP_DUMP_PAYLOADS": "1"]) == true)
        #expect(WhoopClient.shouldDumpPayloads(["WHOOP_DUMP_PAYLOADS": "0"]) == false)
        #expect(WhoopClient.shouldDumpPayloads(["WHOOP_DUMP_PAYLOADS": "true"]) == false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WhoopDumpGateTests`
Expected: FAIL, "type 'WhoopClient' has no member 'shouldDumpPayloads'"

- [ ] **Step 3: Add the gate and the dump**

In `WhoopClient.swift`:

```swift
/// TEMPORARY. Exists only to capture a real `/v2/activity/workout` payload so
/// its DTO can be written against fact rather than documentation. Deleted in the
/// same change that lands the workout DTO. A debug path that logs a user's
/// biometrics is not something to leave behind a flag.
static func shouldDumpPayloads(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    environment["WHOOP_DUMP_PAYLOADS"] == "1"
}
```

Inside `get`, immediately after the status-code switch and before decoding:

```swift
if WhoopClient.shouldDumpPayloads() {
    whoopClientLog.debug("\(path, privacy: .public) page \(pages, privacy: .public): \(String(decoding: data, as: UTF8.self), privacy: .public)")
}
```

Nothing else changes in this task. `WhoopSync` keeps calling the three typed collection methods and `derivation.derive(...)` exactly as Task 6 left them.

Raw archiving is deliberately NOT wired up here. It needs an untyped page reader that extracts each record's provider id, and the shape of a workout's id is one of the things the capture is for. Doing it now would mean writing it twice. It lands in Task 8, alongside the workout endpoint that needs the same reader.

- [ ] **Step 5: Run the suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopClient.swift \
        LifeOSKit/Tests/IntegrationsTests/WhoopPaginationTests.swift
git commit -m "chore(whoop): add a temporary payload dump for capturing the workout shape"
```

- [ ] **Step 7: GATE. Capture the workout payload**

Set `WHOOP_DUMP_PAYLOADS=1` in the Xcode scheme's run environment, run the app on a device or simulator with a connected Whoop account, trigger a sync from Settings, and copy the `whoop-client` log lines from Console.

**Stop here.** Task 8 cannot begin until that payload exists. Hand it back before continuing.

---

### Task 8: Workouts, raw archiving, and removing the dump

Requires the payload captured in Task 7.

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/WhoopClient.swift`
- Modify: `LifeOSKit/Sources/Integrations/WhoopSamples.swift`
- Modify: `LifeOSKit/Sources/Integrations/WhoopDerivation.swift`
- Modify: `LifeOSKit/Sources/Integrations/WhoopSync.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/WhoopWireFormatTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 to 7.
- Produces: `WhoopWorkoutSample`, `WhoopClient.workouts(accessToken:since:until:)`, raw archiving wired into `WhoopSync.sync`.

- [ ] **Step 1: Add the captured payload as a fixture**

Add the real payload to `WhoopWireFormatTests.swift` as `workoutJSON`, scrubbing the values but keeping every field name and the timestamp format exactly as received, matching the convention the other three fixtures already follow.

- [ ] **Step 2: Write the failing test**

```swift
@Test func workoutFieldsMapToTheSample() throws {
    let page = try WhoopClient.decoder.decode(
        WhoopDTOs.Page<WhoopDTOs.WorkoutRecord>.self, from: Data(workoutJSON.utf8)
    )
    let record = try #require(page.records.first)
    #expect(record.id != nil)
    #expect(record.start.timeIntervalSince1970 > 0)
    #expect(record.score?.strain != nil)
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --package-path LifeOSKit --filter WhoopWireFormatTests`
Expected: FAIL, "no member 'WorkoutRecord'"

- [ ] **Step 4: Write the DTO, the sample, and the client call**

The `Score` field names below are the ONLY thing taken from the captured payload rather than written in advance. Correct them to match what was actually received; everything else is fixed.

```swift
// In WhoopDTOs, alongside the other three:
struct WorkoutRecord: Decodable {
    let id: String?
    let start: Date
    let end: Date
    let sport_name: String?
    let score_state: String?
    let score: Score?

    struct Score: Decodable {
        let strain: Double?
        let kilojoule: Double?
        let average_heart_rate: Double?
        let max_heart_rate: Double?
        let distance_meter: Double?
    }
}
```

```swift
// In WhoopSamples.swift:
public struct WhoopWorkoutSample: Sendable, Equatable {
    public let externalID: String
    public let start: Date
    public let end: Date
    public let sportName: String
    public let strain: Double?
    public let energyKcal: Double?
    public let averageHR: Double?
    public let maxHR: Double?
    public let distanceMeters: Double?

    public init(externalID: String, start: Date, end: Date, sportName: String,
                strain: Double? = nil, energyKcal: Double? = nil, averageHR: Double? = nil,
                maxHR: Double? = nil, distanceMeters: Double? = nil) {
        self.externalID = externalID
        self.start = start
        self.end = end
        self.sportName = sportName
        self.strain = strain
        self.energyKcal = energyKcal
        self.averageHR = averageHR
        self.maxHR = maxHR
        self.distanceMeters = distanceMeters
    }

    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}
```

```swift
// In WhoopClient:
public func workouts(accessToken: String, since: Date, until: Date = .now) async throws -> [WhoopWorkoutSample] {
    let records: [WhoopDTOs.WorkoutRecord] =
        try await get("activity/workout", accessToken: accessToken, since: since, until: until)
    return records
        .filter { WhoopDTOs.isScored($0.score_state) }
        .compactMap { record in
            // A workout with no id cannot be upserted, and inserting it would
            // add a duplicate on every sync.
            guard let id = record.id else { return nil }
            return WhoopWorkoutSample(
                externalID: id,
                start: record.start,
                end: record.end,
                sportName: record.sport_name ?? "Workout",
                strain: record.score?.strain,
                energyKcal: record.score?.kilojoule.map { $0 / 4.184 },
                averageHR: record.score?.average_heart_rate,
                maxHR: record.score?.max_heart_rate,
                distanceMeters: record.score?.distance_meter
            )
        }
}
```

- [ ] **Step 5: Write the failing test for raw splitting**

Append to `WhoopPaginationTests.swift`:

```swift
@Suite struct WhoopRawSplitTests {
    @Test func eachRecordBecomesItsOwnPayloadKeyedByID() throws {
        let page = #"{"records":[{"id":"a","v":1},{"id":"b","v":2}],"next_token":null}"#
        let split = try WhoopRawSplit.records(inPage: Data(page.utf8))
        #expect(split.map(\.externalID) == ["a", "b"])
        #expect(String(decoding: split[0].payload, as: UTF8.self).contains("\"v\":1"))
    }

    /// Recovery records have no id of their own; they are keyed by the cycle
    /// they score. Without this they would all collide on one archive row.
    @Test func recoveryIsKeyedByItsCycle() throws {
        let page = #"{"records":[{"cycle_id":123,"score_state":"SCORED"}],"next_token":null}"#
        let split = try WhoopRawSplit.records(inPage: Data(page.utf8))
        #expect(split.map(\.externalID) == ["123"])
    }

    @Test func numericIDsBecomeStrings() throws {
        let page = #"{"records":[{"id":99}],"next_token":null}"#
        #expect(try WhoopRawSplit.records(inPage: Data(page.utf8)).map(\.externalID) == ["99"])
    }

    /// A record with no usable identity is skipped rather than archived under a
    /// made-up key that a later sync could never match.
    @Test func recordsWithNoIdentityAreSkipped() throws {
        let page = #"{"records":[{"noise":1},{"id":"ok"}],"next_token":null}"#
        #expect(try WhoopRawSplit.records(inPage: Data(page.utf8)).map(\.externalID) == ["ok"])
    }
}
```

Run: `swift test --package-path LifeOSKit --filter WhoopRawSplitTests`
Expected: FAIL, "cannot find 'WhoopRawSplit' in scope"

- [ ] **Step 6: Implement raw splitting and return raw pages from `get`**

Create `LifeOSKit/Sources/Integrations/WhoopRawSplit.swift`:

```swift
import Foundation

/// Splits a page envelope into one payload per record, keyed by that record's
/// provider id, so the archive stores exactly what arrived rather than a
/// re-encoding of a decoded struct.
enum WhoopRawSplit {
    static func records(inPage data: Data) throws -> [(externalID: String, payload: Data)] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [[String: Any]] else { return [] }

        return try records.compactMap { record in
            guard let id = identifier(in: record) else { return nil }
            return (id, try JSONSerialization.data(withJSONObject: record))
        }
    }

    /// Recovery carries no `id`; it is identified by the cycle it scores.
    static func identifier(in record: [String: Any]) -> String? {
        if let id = record["id"] as? String { return id }
        if let id = record["id"] as? Int { return String(id) }
        if let id = record["cycle_id"] as? Int { return String(id) }
        if let id = record["cycle_id"] as? String { return id }
        return nil
    }
}
```

Change `get` to hand back the raw pages alongside the records, so archiving costs no extra requests:

```swift
struct Fetched<Record: Decodable> {
    let records: [Record]
    let rawPages: [Data]
}
```

`get` accumulates `rawPages.append(data)` inside the existing loop and returns `Fetched`. Each public collection method keeps returning `[Sample]` and additionally stores its raw pages on a `private(set) var lastRawPages: [String: [Data]]`. Simpler and preferred: give each collection method a sibling that returns both, and have `WhoopSync` call the sibling:

```swift
public func recoveriesRaw(accessToken: String, since: Date, until: Date = .now)
    async throws -> (samples: [WhoopRecoverySample], rawPages: [Data])
```

Implement one sibling per collection, each reusing the existing mapping. The four public sample-only methods remain for tests and callers that do not archive.

- [ ] **Step 7: Store workouts in `WhoopDerivation`**

Add a `workouts` parameter to `derive` and a record upsert, matching the sleep-record pattern from Task 6:

```swift
public func derive(
    recoveries: [WhoopRecoverySample] = [],
    sleeps: [WhoopSleepSample] = [],
    cycles: [WhoopCycleSample] = [],
    workouts: [WhoopWorkoutSample] = []
) throws {
    try storeSleepRecords(sleeps)
    try storeWorkoutRecords(workouts)
    // ...existing day indexing unchanged...
}

private func storeWorkoutRecords(_ workouts: [WhoopWorkoutSample]) throws {
    for sample in workouts {
        try store.upsertWorkoutRecord(
            externalID: sample.externalID,
            start: sample.start,
            durationMinutes: sample.durationMinutes,
            activityName: sample.sportName
        ) { record in
            record.energyKcal = sample.energyKcal
            record.strain = sample.strain
            record.averageHR = sample.averageHR
            record.maxHR = sample.maxHR
            record.distanceMeters = sample.distanceMeters
        }
    }
}
```

Add the matching upsert to `MetricsStore`, mirroring `upsertSleepRecord` from Task 6 exactly:

```swift
public func upsertWorkoutRecord(
    externalID: String,
    start: Date,
    durationMinutes: Int,
    activityName: String,
    apply: (WorkoutRecord) -> Void
) throws {
    let existing = try context.fetch(
        FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == externalID })
    ).first

    let record = existing ?? WorkoutRecord(
        externalID: externalID, start: start,
        durationMinutes: durationMinutes, activityName: activityName
    )
    if existing == nil { context.insert(record) }
    record.start = start
    record.durationMinutes = durationMinutes
    record.activityName = activityName
    apply(record)
    try context.save()
}
```

Roll workout minutes into the day row inside the existing `upsertBatch`, on the same nil-never-overwrites rule:

```swift
// Inside the upsertBatch closure, after the cycle fields:
let dayWorkouts = workouts.filter { calendar.isDate($0.start, inSameDayAs: day) }
if !dayWorkouts.isEmpty {
    row.exerciseMinutes = dayWorkouts.reduce(0) { $0 + $1.durationMinutes }
}
```

- [ ] **Step 8: Wire archiving and workouts into the sync**

In `WhoopSync.sync`, replace the three fetches with their raw siblings, archive, then derive:

```swift
let recovery = try await client.recoveriesRaw(accessToken: current.accessToken, since: since, until: now)
let sleep = try await client.sleepsRaw(accessToken: current.accessToken, since: since, until: now)
let cycle = try await client.cyclesRaw(accessToken: current.accessToken, since: since, until: now)
let workout = try await client.workoutsRaw(accessToken: current.accessToken, since: since, until: now)

// Archive first: derivation reads from the archive on a re-derive, and a
// payload that was never stored cannot be re-derived from.
for (kind, pages) in [("recovery", recovery.rawPages), ("sleep", sleep.rawPages),
                      ("cycle", cycle.rawPages), ("workout", workout.rawPages)] {
    let split = try pages.flatMap { try WhoopRawSplit.records(inPage: $0) }
    try archive.store(split.map { (kind: kind, externalID: $0.externalID, payload: $0.payload) })
}

try derivation.derive(recoveries: recovery.samples, sleeps: sleep.samples,
                      cycles: cycle.samples, workouts: workout.samples)
return Set(recovery.samples.map(\.date) + cycle.samples.map(\.date)).count
```

`WhoopSync` gains an `archive: WhoopArchive` stored property and initialiser parameter. Update its construction in `WhoopConnectionViewModel.swift` to pass one, built from the same context as the store.

- [ ] **Step 9: Remove the dump path**

Delete `shouldDumpPayloads`, its call inside `get`, and the whole `WhoopDumpGateTests` suite. This is not optional: a debug path that logs a user's biometrics is not something to leave behind a flag.

Verify nothing survives:

```bash
grep -rn "WHOOP_DUMP_PAYLOADS\|shouldDumpPayloads" LifeOSKit LIfeOS
```
Expected: no matches.

- [ ] **Step 10: Run the suite and build the app**

Run: `swift test --package-path LifeOSKit`
Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build`
Expected: both pass

- [ ] **Step 11: Commit**

```bash
git add -A LifeOSKit LIfeOS
git commit -m "feat(whoop): ingest workouts and archive raw payloads on every sync"
```
