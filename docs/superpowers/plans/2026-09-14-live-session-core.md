# Live Session Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a running activity a live readout of heart-rate zone, estimated effort, calories and "battery left", shown in a redesigned gradient Live Activity and a small Liquid Glass HUD, with the WHOOP sensor reconnecting on its own.

**Architecture:** A pure effort model in the `Integrations` package (zones, effort accumulator, capacity, ceiling, push state) feeds one `LiveSessionReadout` value type that lives in `AppSurfaces` so the widget extension can decode it. `ActivityRecorder` computes the readout on every change and hands it to a throttled Live Activity controller and to the HUD. Nothing here talks to a server.

**Tech Stack:** Swift 6, SwiftUI, ActivityKit, WidgetKit, HealthKit, CoreBluetooth, SwiftData, Swift Testing. iOS 26 Liquid Glass (`glassEffect`).

**Spec:** `docs/superpowers/specs/2026-09-14-live-session-core-design.md`

## Global Constraints

- Deployment target iOS 26.0, Swift 6.0, package platforms `.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")`. Package tests run on macOS, so package code that needs iOS-only frameworks stays behind `#if os(iOS)`.
- Tests are Swift Testing (`import Testing`, `@Test`, `#expect`). Never XCTest.
- A missing value is never shown as zero. Every optional stays optional through to the UI, which renders an en dash for absence.
- Effort is always labelled estimated ("EST" eyebrow or the word "estimated").
- Copy has no em dashes. Commit messages are conventional commits (`type(scope): imperative summary`) with a short body, and carry no Co-Authored-By or other attribution trailer.
- Work happens in the worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/live-session-core` on branch `feat/live-session-core`. Never commit to `main`. Never use bare `git stash`.
- Package tests: `cd LifeOSKit && swift test --filter <Suite>`. App build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build`. Widget target builds as part of the app scheme.
- Per-account state uses `UserDefaults.currentAccount` (from `Persistence/UserScope.swift`). Design previews pass their own suite.
- Colours come from `LifeOSTokens` and `ModuleHue` in `DesignSystem/Tokens.swift`; the widget target links `DesignSystem` from Task 9 onward.

## File map

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift` (new) | `PushState`, `LiveSessionReadout`, `LiveActivityThrottle`. Foundation only. |
| `LifeOSKit/Sources/AppSurfaces/WorkoutActivityAttributes.swift` | `ContentState` becomes a typealias of `LiveSessionReadout`. |
| `LifeOSKit/Sources/Integrations/LiveEffort.swift` (new) | `HeartRateZones`, `EffortAccumulator`, `EffortCeiling`, `Capacity`, `RecoveryDay`, `CapacityMath`, `EffortMath`, `LiveReadoutBuilder`. Pure. |
| `LifeOSKit/Sources/Integrations/WhoopAutoPair.swift` (new) | Pure choice of which discovered sensor to auto-pair. |
| `LifeOSKit/Sources/DesignSystem/Tokens.swift` | Three push-state tints. |
| `LifeOSKit/Package.swift` | `Integrations` depends on `AppSurfaces`. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift` | Zones, capacity, effort accrual, readout, draft fields, auto-connect call. |
| `LIfeOS/Features/Activity/ViewModel/LiveHeartRateSensor.swift` | Remembered peripheral, `reconnectIfRemembered`, `autoPairWhoop`. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift` | Capacity and remembered-sensor checks. |
| `LIfeOS/App/Surfaces/WorkoutLiveActivityController.swift` | `sync(_ readout:timer:icon:)` with throttle. |
| `AlmanacWidgets/WorkoutLiveActivity.swift` | Gradient lock screen and Dynamic Island. |
| `LIfeOS/Features/Activity/View/SessionHUD.swift` (new) | The glass capsule, collapsed and expanded. |
| `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` | In-session gradient hero, HUD, glass tiles, birth-date hint. |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | `--live` fixture for screenshots. |
| `LIfeOS/App/RootView.swift` | Passes WHOOP connection state to the recorder. |
| `LIfeOS.xcodeproj/project.pbxproj` | `DesignSystem` linked into `AlmanacWidgets`. |
| `LifeOSKit/Tests/AppSurfacesTests/LiveSessionReadoutTests.swift` (new) | Readout codability, throttle. |
| `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift` (new) | Zones, effort, capacity, battery, push, builder, auto-pair. |
| `docs/design/live-session/` (new) | Design QA captures and report. |

---

### Task 1: Bring the uncommitted activity foundation onto the branch

The recorder, sensor, Live Activity, surfaces and watch target exist only as uncommitted files in the main checkout at `/Users/shivvyas/LIfeOS`. This branch needs them.

**Files:**
- Create/Modify: everything `git status` in the main checkout reports as modified or untracked (26 modified tracked files, about 20 untracked paths including `AlmanacWidgets/`, `AlmanacWatch/`, `LIfeOS/App/Surfaces/`, `LIfeOS/Features/Activity/**`, `LifeOSKit/Sources/AppSurfaces/`).

**Interfaces:**
- Produces: `ActivityRecorder`, `LiveHeartRateSensor`, `WorkoutLiveActivityController`, `WorkoutActivityAttributes`, `ActivitySessionState`, `SurfaceRoute` exactly as they are in the main checkout today.

- [ ] **Step 1: Confirm the main checkout still holds the foundation**

Run: `git -C /Users/shivvyas/LIfeOS status --short | head -60`
Expected: lines for `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift` (`??`), `AlmanacWidgets/` (`??`), `LifeOSKit/Sources/AppSurfaces/` (`??`), and ` M LIfeOS/App/RootView.swift`. If the list is empty because a peer committed it, run `git log --oneline -5 main` to find that commit, `git merge <sha>` into this branch instead, and skip to Step 5.

- [ ] **Step 2: Copy the tracked modifications as a patch**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/live-session-core
SCRATCH=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/a96098d0-f675-4735-b362-991438ea3ab1/scratchpad
mkdir -p "$SCRATCH"
git -C /Users/shivvyas/LIfeOS diff --binary > "$SCRATCH/foundation.patch"
git apply --index "$SCRATCH/foundation.patch"
git status --short | wc -l
```
Expected: the count equals the number of ` M` lines from Step 1 (26 at the time of writing).

- [ ] **Step 3: Copy the untracked files and the secrets file**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/live-session-core
git -C /Users/shivvyas/LIfeOS ls-files --others --exclude-standard -z \
  | rsync -a --files-from=- --from0 /Users/shivvyas/LIfeOS/ ./
cp /Users/shivvyas/LIfeOS/Config/Secrets.xcconfig Config/Secrets.xcconfig
git add -A
git status --short | grep -c .
```
Expected: `Config/Secrets.xcconfig` does not appear in `git status` (it is ignored). Everything else from Step 1 is staged.

- [ ] **Step 4: Run the package tests and build the app**

Run: `cd LifeOSKit && swift test 2>&1 | tail -5`
Expected: `Test run with N tests passed after ...` with zero failures (about 1,200 tests).

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(activity): native recorder, sensors, surfaces and watch dashboard

Bring the uncommitted health and activity delivery onto a branch: the
HKWorkoutSession recorder with drafts, the Bluetooth heart-rate sensor,
the timer Live Activity, widgets, the watch dashboard, notifications and
the profile sharing card. Foundation for the live session core."
```

---

### Task 2: `PushState` and `LiveSessionReadout` in AppSurfaces

**Files:**
- Create: `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift`
- Modify: `LifeOSKit/Sources/AppSurfaces/WorkoutActivityAttributes.swift`
- Modify: `LifeOSKit/Package.swift`
- Test: `LifeOSKit/Tests/AppSurfacesTests/LiveSessionReadoutTests.swift`

**Interfaces:**
- Produces:
  - `public enum PushState: String, Codable, Hashable, Sendable { case easy, onTrack, nearLimit, overLimit }` with `var headline: String`.
  - `public struct LiveSessionReadout: Codable, Hashable, Sendable` with the fields below, `timerAnchor: Date?`, `isPaused: Bool`.
  - `WorkoutActivityAttributes.ContentState == LiveSessionReadout`.
  - `Integrations` can `import AppSurfaces`.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/AppSurfacesTests/LiveSessionReadoutTests.swift`:

```swift
import Foundation
import Testing
@testable import AppSurfaces

struct LiveSessionReadoutTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func readoutRoundTripsAndKeepsAbsence() throws {
        var readout = LiveSessionReadout(elapsed: 90, runningSince: start, push: .onTrack)
        readout.heartRate = 142; readout.zone = 4; readout.effort = 9.3
        readout.calories = 210; readout.batteryPercent = 62; readout.capacitySource = "whoop"
        readout.ceilingMaxZone = 4; readout.ceilingTarget = 10...14
        let data = try JSONEncoder().encode(readout)
        let back = try JSONDecoder().decode(LiveSessionReadout.self, from: data)
        #expect(back == readout)
        #expect(back.distanceMeters == nil)
        #expect(back.timerAnchor == start.addingTimeInterval(-90))
        #expect(!back.isPaused)
    }

    @Test func pausedReadoutHasNoAnchor() {
        let readout = LiveSessionReadout(elapsed: 30, runningSince: nil, push: .easy)
        #expect(readout.timerAnchor == nil)
        #expect(readout.isPaused)
    }

    @Test func pushHeadlinesAreWords() {
        #expect(PushState.easy.headline == "Easy going")
        #expect(PushState.onTrack.headline == "On track")
        #expect(PushState.nearLimit.headline == "Near your limit")
        #expect(PushState.overLimit.headline == "Over your target")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter LiveSessionReadoutTests 2>&1 | tail -5`
Expected: compile error, `cannot find 'LiveSessionReadout' in scope`.

- [ ] **Step 3: Write the types**

Create `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift`:

```swift
import Foundation

/// How hard the person is going against today's ceiling. Drives colour and
/// the headline on every surface; the words live here so they never drift.
public enum PushState: String, Codable, Hashable, Sendable {
    case easy, onTrack, nearLimit, overLimit

    public var headline: String {
        switch self {
        case .easy: "Easy going"
        case .onTrack: "On track"
        case .nearLimit: "Near your limit"
        case .overLimit: "Over your target"
        }
    }
}

/// The one value every live surface renders: the in-app HUD, the lock screen
/// and the Dynamic Island. Every reading is optional because a missing
/// sensor is not a zero. `elapsed` is the accumulated time while running or
/// paused; `runningSince` is nil while paused, which is how a surface knows.
public struct LiveSessionReadout: Codable, Hashable, Sendable {
    public var elapsed: TimeInterval
    public var runningSince: Date?
    public var heartRate: Int?
    public var zone: Int?
    /// Estimated, on WHOOP's 0 to 21 scale, rounded to a tenth before publishing.
    public var effort: Double?
    public var calories: Int?
    public var distanceMeters: Int?
    public var batteryPercent: Int?
    /// "whoop" or "health", for the eyebrow that says where the battery came from.
    public var capacitySource: String?
    public var ceilingMaxZone: Int?
    public var ceilingTarget: ClosedRange<Double>?
    public var push: PushState

    public init(elapsed: TimeInterval, runningSince: Date?, push: PushState) {
        self.elapsed = elapsed
        self.runningSince = runningSince
        self.push = push
    }

    /// Anchor for `Text(timerInterval:)`, so the system ticks the timer
    /// without an update per second.
    public var timerAnchor: Date? { runningSince?.addingTimeInterval(-elapsed) }
    public var isPaused: Bool { runningSince == nil }
}
```

Replace the body of `LifeOSKit/Sources/AppSurfaces/WorkoutActivityAttributes.swift` with:

```swift
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias ContentState = LiveSessionReadout
    public let sessionID: UUID
    public let name: String
    public let icon: String
    public init(sessionID: UUID, name: String, icon: String) {
        self.sessionID = sessionID; self.name = name; self.icon = icon
    }
}
#endif
```

In `LifeOSKit/Package.swift` change the `Integrations` target line to:

```swift
        .target(name: "Integrations", dependencies: ["Persistence", "AppSurfaces"]),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter "LiveSessionReadoutTests|AppSurfacesTests" 2>&1 | tail -3`
Expected: all pass. Then `swift build` to confirm `Integrations` still compiles with the new dependency.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift LifeOSKit/Sources/AppSurfaces/WorkoutActivityAttributes.swift LifeOSKit/Package.swift LifeOSKit/Tests/AppSurfacesTests/LiveSessionReadoutTests.swift
git commit -m "feat(surfaces): a live session readout the widget can decode

One value type for heart rate, zone, estimated effort, calories, battery
and push state. The Live Activity content state becomes this struct, and
Integrations gains AppSurfaces as a dependency so the effort model can
build it."
```

---

### Task 3: Heart-rate zones

**Files:**
- Create: `LifeOSKit/Sources/Integrations/LiveEffort.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`

**Interfaces:**
- Produces: `public struct HeartRateZones: Equatable, Sendable { let maxHeartRate: Int; init?(birthDate: Date?, on: Date, calendar: Calendar); func zone(for bpm: Int) -> Int }`.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`:

```swift
import Foundation
import Testing
import AppSurfaces
@testable import Integrations

struct LiveEffortTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private var today: Date { day(2026, 9, 14) }
    private var thirtyYearsOld: Date { day(1996, 6, 1) }

    @Test func zonesFollowTanakaAndWhoopBands() throws {
        let zones = try #require(HeartRateZones(birthDate: thirtyYearsOld, on: today, calendar: calendar))
        #expect(zones.maxHeartRate == 187)
        #expect(zones.zone(for: 90) == 0)
        #expect(zones.zone(for: 94) == 1)
        #expect(zones.zone(for: 131) == 3)
        #expect(zones.zone(for: 169) == 5)
    }

    @Test func noBirthDateMeansNoZones() {
        #expect(HeartRateZones(birthDate: nil, on: today, calendar: calendar) == nil)
        #expect(HeartRateZones(birthDate: day(2025, 1, 1), on: today, calendar: calendar) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -5`
Expected: compile error, `cannot find 'HeartRateZones' in scope`.

- [ ] **Step 3: Write the zones**

Create `LifeOSKit/Sources/Integrations/LiveEffort.swift`:

```swift
import Foundation
import AppSurfaces

/// Heart-rate zones from age. Tanaka's estimate of maximum heart rate and
/// WHOOP's zone bands, so the number on the HUD agrees with the number in
/// the app the person already trusts.
///
/// No birth date means no zones, never a guessed maximum: a zone built on an
/// assumed age would be a reading the person never gave.
public struct HeartRateZones: Equatable, Sendable {
    public let maxHeartRate: Int

    public init?(birthDate: Date?, on date: Date = .now, calendar: Calendar = .current) {
        guard let birthDate,
              let age = calendar.dateComponents([.year], from: birthDate, to: date).year,
              (10...120).contains(age) else { return nil }
        maxHeartRate = Int((208.0 - 0.7 * Double(age)).rounded())
    }

    /// 0 below half of maximum, then one zone per ten percent up to 5.
    public func zone(for bpm: Int) -> Int {
        let fraction = Double(bpm) / Double(maxHeartRate)
        switch fraction {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -3`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/LiveEffort.swift LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift
git commit -m "feat(effort): heart-rate zones from age

Tanaka maximum and WHOOP's five bands. No birth date yields no zones
rather than a guessed maximum."
```

---

### Task 4: Effort accumulator

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/LiveEffort.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`

**Interfaces:**
- Produces: `public struct EffortAccumulator: Codable, Equatable, Sendable { init(load: Double = 0); private(set) var load: Double; mutating func add(zone: Int, seconds: TimeInterval); var effort: Double; static func credit(previous: Date?, at: Date) -> TimeInterval }`.

- [ ] **Step 1: Write the failing tests**

Append inside `struct LiveEffortTests`:

```swift
    @Test func effortCalibrationPoints() {
        var steadyZone3 = EffortAccumulator()
        steadyZone3.add(zone: 3, seconds: 3600)
        #expect(abs(steadyZone3.effort - 12) < 1)

        var easyZone2 = EffortAccumulator()
        easyZone2.add(zone: 2, seconds: 1800)
        #expect(abs(easyZone2.effort - 6) < 1)

        var hard = EffortAccumulator()
        hard.add(zone: 4, seconds: 2700); hard.add(zone: 5, seconds: 2700)
        #expect(abs(hard.effort - 18) < 1)

        #expect(EffortAccumulator().effort == 0)
    }

    @Test func effortIsBoundedAndMonotonic() {
        var effort = EffortAccumulator()
        var last = 0.0
        for _ in 0..<100 {
            effort.add(zone: 5, seconds: 600)
            #expect(effort.effort >= last)
            last = effort.effort
        }
        #expect(last < 21)
        effort.add(zone: 0, seconds: 3600)
        #expect(effort.effort == last)
        effort.add(zone: 9, seconds: 60); effort.add(zone: 3, seconds: -5)
        #expect(effort.effort == last)
    }

    @Test func creditCapsGapsAndStartsAtZero() {
        let now = today
        #expect(EffortAccumulator.credit(previous: nil, at: now) == 0)
        #expect(EffortAccumulator.credit(previous: now.addingTimeInterval(-40), at: now) == 5)
        #expect(EffortAccumulator.credit(previous: now.addingTimeInterval(-2), at: now) == 2)
        #expect(EffortAccumulator.credit(previous: now.addingTimeInterval(3), at: now) == 0)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -5`
Expected: compile error, `cannot find 'EffortAccumulator' in scope`.

- [ ] **Step 3: Write the accumulator**

Append to `LifeOSKit/Sources/Integrations/LiveEffort.swift`:

```swift
/// Estimated effort on WHOOP's 0 to 21 scale.
///
/// Seconds in each zone add a weight to a running load, and the load maps
/// through a saturating curve so a long day approaches 21 without reaching
/// it. The constants are pinned by calibration tests: a steady hour in zone 3
/// is about 12, a hard ninety minutes about 18. Retuning is a deliberate
/// change with a diff, not a drift.
public struct EffortAccumulator: Codable, Equatable, Sendable {
    public static let weights: [Double] = [0, 0.15, 0.28, 0.35, 0.45, 0.63]
    public static let scale = 1500.0
    /// A gap in the stream is not effort that was measured. One reading
    /// credits at most this many seconds.
    public static let maxCredit: TimeInterval = 5

    public private(set) var load: Double

    public init(load: Double = 0) { self.load = max(0, load) }

    public mutating func add(zone: Int, seconds: TimeInterval) {
        guard seconds > 0, Self.weights.indices.contains(zone) else { return }
        load += Self.weights[zone] * seconds
    }

    public var effort: Double { 21 * (1 - exp(-load / Self.scale)) }

    /// Seconds to credit a reading at `date` given the previous reading.
    public static func credit(previous: Date?, at date: Date) -> TimeInterval {
        guard let previous else { return 0 }
        return min(maxCredit, max(0, date.timeIntervalSince(previous)))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -3`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/LiveEffort.swift LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift
git commit -m "feat(effort): estimated effort from seconds in zone

Zone weights and a saturating map onto the 0 to 21 scale, pinned by
calibration tests. A gap in the stream credits at most five seconds."
```

---

### Task 5: Capacity, ceiling, battery and push state

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/LiveEffort.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`

**Interfaces:**
- Produces:
  - `public struct EffortCeiling: Codable, Equatable, Sendable { let maxZone: Int; let targetEffort: ClosedRange<Double>; static let green, yellow, red, conservative; static func forCapacity(_ percent: Int) -> EffortCeiling }`
  - `public struct Capacity: Codable, Equatable, Sendable { enum Source: String, Codable { case whoop, health }; let percent: Int; let source: Source; let measuredOn: Date; var ceiling: EffortCeiling }`
  - `public struct RecoveryDay: Equatable, Sendable { date, whoopRecoveryPct, whoopIsCalibrating, sleepPerformancePct, hrvMs, sleepMinutes }`
  - `public enum CapacityMath { static func capacity(days: [RecoveryDay], now: Date, calendar: Calendar) -> Capacity? }`
  - `public enum EffortMath { static func batteryRemaining(capacity: Int, effort: Double, ceiling: EffortCeiling) -> Int; static func pushState(zone: Int?, effort: Double, ceiling: EffortCeiling) -> PushState }`

- [ ] **Step 1: Write the failing tests**

Append inside `struct LiveEffortTests`:

```swift
    private func recovery(_ date: Date, whoop: Double? = nil, calibrating: Bool? = nil, sleepPerf: Double? = nil,
                          hrv: Double? = nil, sleep: Int? = nil) -> RecoveryDay {
        RecoveryDay(date: calendar.startOfDay(for: date), whoopRecoveryPct: whoop, whoopIsCalibrating: calibrating,
                    sleepPerformancePct: sleepPerf, hrvMs: hrv, sleepMinutes: sleep)
    }
    private func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today)! }

    @Test func whoopRecoveryBlendsSleepAndSetsGreenCeiling() throws {
        let capacity = try #require(CapacityMath.capacity(days: [recovery(today, whoop: 80, sleepPerf: 90)], now: today, calendar: calendar))
        #expect(capacity.percent == 82)
        #expect(capacity.source == .whoop)
        #expect(capacity.ceiling == .green)
        #expect(capacity.measuredOn == calendar.startOfDay(for: today))
    }

    @Test func yesterdayRecoveryStandsInUntilTodaySyncs() throws {
        let capacity = try #require(CapacityMath.capacity(days: [recovery(daysAgo(1), whoop: 40)], now: today, calendar: calendar))
        #expect(capacity.percent == 40)
        #expect(capacity.ceiling == .yellow)
        #expect(CapacityMath.capacity(days: [recovery(daysAgo(2), whoop: 40)], now: today, calendar: calendar) == nil)
    }

    @Test func calibratingWhoopFallsThroughToHealth() throws {
        let days = [recovery(today, whoop: 80, calibrating: true, hrv: 60, sleep: 450)]
            + (1...3).map { recovery(daysAgo($0), hrv: 60) }
        let capacity = try #require(CapacityMath.capacity(days: days, now: today, calendar: calendar))
        #expect(capacity.source == .health)
        #expect(capacity.percent == 65)
        #expect(capacity.ceiling == .yellow)
    }

    @Test func healthCapacityNeedsABaselineAndRespondsToSleep() throws {
        #expect(CapacityMath.capacity(days: [recovery(today, hrv: 60), recovery(daysAgo(1), hrv: 60)], now: today, calendar: calendar) == nil)
        let short = [recovery(today, hrv: 60, sleep: 300)] + (1...3).map { recovery(daysAgo($0), hrv: 60) }
        #expect(try #require(CapacityMath.capacity(days: short, now: today, calendar: calendar)).percent == 55)
        let strong = [recovery(today, hrv: 72)] + (1...3).map { recovery(daysAgo($0), hrv: 60) }
        #expect(try #require(CapacityMath.capacity(days: strong, now: today, calendar: calendar)).percent == 90)
        #expect(CapacityMath.capacity(days: [], now: today, calendar: calendar) == nil)
    }

    @Test func batteryDrainsAgainstTheTargetTop() {
        #expect(EffortMath.batteryRemaining(capacity: 60, effort: 7, ceiling: .yellow) == 30)
        #expect(EffortMath.batteryRemaining(capacity: 60, effort: 15, ceiling: .yellow) == 0)
        #expect(EffortMath.batteryRemaining(capacity: 60, effort: 0, ceiling: .yellow) == 60)
    }

    @Test func pushStateFollowsZoneAndEffort() {
        #expect(EffortMath.pushState(zone: 5, effort: 8, ceiling: .yellow) == .overLimit)
        #expect(EffortMath.pushState(zone: 3, effort: 15, ceiling: .yellow) == .overLimit)
        #expect(EffortMath.pushState(zone: 4, effort: 8, ceiling: .yellow) == .nearLimit)
        #expect(EffortMath.pushState(zone: 3, effort: 13, ceiling: .yellow) == .nearLimit)
        #expect(EffortMath.pushState(zone: 2, effort: 3, ceiling: .yellow) == .easy)
        #expect(EffortMath.pushState(zone: 3, effort: 3, ceiling: .yellow) == .onTrack)
        #expect(EffortMath.pushState(zone: nil, effort: 11, ceiling: .yellow) == .onTrack)
        #expect(EffortMath.pushState(zone: nil, effort: 3, ceiling: .yellow) == .easy)
    }

    @Test func ceilingBands() {
        #expect(EffortCeiling.forCapacity(67) == .green)
        #expect(EffortCeiling.forCapacity(66) == .yellow)
        #expect(EffortCeiling.forCapacity(34) == .yellow)
        #expect(EffortCeiling.forCapacity(33) == .red)
        #expect(EffortCeiling.conservative == .yellow)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -5`
Expected: compile error, `cannot find 'RecoveryDay' in scope`.

- [ ] **Step 3: Write capacity and push**

Append to `LifeOSKit/Sources/Integrations/LiveEffort.swift`:

```swift
/// How far the person may push today: the highest zone worth visiting and
/// the effort range to aim for. Bands mirror WHOOP's recovery colours.
public struct EffortCeiling: Codable, Equatable, Sendable {
    public let maxZone: Int
    public let targetEffort: ClosedRange<Double>

    public init(maxZone: Int, targetEffort: ClosedRange<Double>) {
        self.maxZone = maxZone; self.targetEffort = targetEffort
    }

    public static let green = EffortCeiling(maxZone: 5, targetEffort: 14...18)
    public static let yellow = EffortCeiling(maxZone: 4, targetEffort: 10...14)
    public static let red = EffortCeiling(maxZone: 3, targetEffort: 4...10)
    /// Used when nothing is known about today. Cautious, without claiming a
    /// capacity that was never measured.
    public static let conservative = yellow

    public static func forCapacity(_ percent: Int) -> EffortCeiling {
        percent >= 67 ? .green : percent >= 34 ? .yellow : .red
    }
}

/// Today's battery: what the person has to spend, and where the number came
/// from. Computed once at session start and kept in the draft.
public struct Capacity: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case whoop, health }
    public let percent: Int
    public let source: Source
    public let measuredOn: Date

    public init(percent: Int, source: Source, measuredOn: Date) {
        self.percent = min(100, max(0, percent)); self.source = source; self.measuredOn = measuredOn
    }
    public var ceiling: EffortCeiling { .forCapacity(percent) }
}

/// One day's recovery inputs, lifted off `DailyMetrics` so the math has no
/// SwiftData in it. `date` is a calendar day start.
public struct RecoveryDay: Equatable, Sendable {
    public let date: Date
    public var whoopRecoveryPct: Double?
    public var whoopIsCalibrating: Bool?
    public var sleepPerformancePct: Double?
    public var hrvMs: Double?
    public var sleepMinutes: Int?

    public init(date: Date, whoopRecoveryPct: Double? = nil, whoopIsCalibrating: Bool? = nil,
                sleepPerformancePct: Double? = nil, hrvMs: Double? = nil, sleepMinutes: Int? = nil) {
        self.date = date; self.whoopRecoveryPct = whoopRecoveryPct; self.whoopIsCalibrating = whoopIsCalibrating
        self.sleepPerformancePct = sleepPerformancePct; self.hrvMs = hrvMs; self.sleepMinutes = sleepMinutes
    }
}

public enum CapacityMath {
    /// WHOOP first, Apple Health second, nothing third. Today's row, or
    /// yesterday's when today has not synced yet; anything older is stale.
    public static func capacity(days: [RecoveryDay], now: Date, calendar: Calendar = .current) -> Capacity? {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let recent = days.filter { $0.date >= yesterday && $0.date <= today }.sorted { $0.date > $1.date }

        if let day = recent.first(where: { $0.whoopRecoveryPct != nil && $0.whoopIsCalibrating != true }),
           let recovery = day.whoopRecoveryPct {
            let blended = day.sleepPerformancePct.map { 0.8 * recovery + 0.2 * $0 } ?? recovery
            return Capacity(percent: Int(blended.rounded()), source: .whoop, measuredOn: day.date)
        }

        if let day = recent.first(where: { $0.hrvMs != nil }), let hrv = day.hrvMs {
            let weekBefore = calendar.date(byAdding: .day, value: -7, to: day.date)!
            let baseline = days.filter { $0.date < day.date && $0.date >= weekBefore }.compactMap(\.hrvMs)
            guard baseline.count >= 3 else { return nil }
            let mean = baseline.reduce(0, +) / Double(baseline.count)
            let ratio = hrv / mean
            // 0.7 of baseline is 20, baseline is 65, 1.2 of baseline is 90.
            var percent = ratio <= 1 ? 20 + (ratio - 0.7) / 0.3 * 45 : 65 + (ratio - 1) / 0.2 * 25
            percent = min(90, max(20, percent))
            if let sleep = day.sleepMinutes {
                percent += min(10, max(-10, Double(sleep - 450) / 60 * 10))
            }
            return Capacity(percent: Int(percent.rounded()), source: .health, measuredOn: day.date)
        }
        return nil
    }
}

public enum EffortMath {
    /// Battery drains as effort approaches the target's top. Zero is a real
    /// event, the budget spent, not a missing value.
    public static func batteryRemaining(capacity: Int, effort: Double, ceiling: EffortCeiling) -> Int {
        let fraction = 1 - effort / ceiling.targetEffort.upperBound
        return max(0, Int((Double(capacity) * fraction).rounded()))
    }

    public static func pushState(zone: Int?, effort: Double, ceiling: EffortCeiling) -> PushState {
        let upper = ceiling.targetEffort.upperBound
        if effort > upper || (zone ?? 0) > ceiling.maxZone { return .overLimit }
        if zone == ceiling.maxZone || effort >= upper - 1.5 { return .nearLimit }
        if effort < ceiling.targetEffort.lowerBound && (zone ?? 0) <= 2 { return .easy }
        return .onTrack
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -3`
Expected: 12 tests pass. If `healthCapacityNeedsABaselineAndRespondsToSleep` disagrees by one point, check the rounding is applied once, at the end, and that sleep adjusts after clamping.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/LiveEffort.swift LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift
git commit -m "feat(effort): capacity, ceiling, battery and push state

Today's battery from WHOOP recovery and sleep, or Apple Health HRV
against a week's baseline, with WHOOP's recovery bands as the ceiling.
Battery drains toward the target's top and push state names the moment."
```

---

### Task 6: Readout builder and Live Activity throttle

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/LiveEffort.swift`
- Modify: `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`, `LifeOSKit/Tests/AppSurfacesTests/LiveSessionReadoutTests.swift`

**Interfaces:**
- Produces:
  - `public enum LiveReadoutBuilder { static func readout(timer: ActivitySessionState, heartRate: Int?, zones: HeartRateZones?, effort: EffortAccumulator, capacity: Capacity?, energyKcal: Double?, distanceMeters: Double?) -> LiveSessionReadout }`
  - `public enum LiveActivityThrottle { static let heartRateStep = 3; static let floor: TimeInterval = 10; static func shouldPublish(previous: LiveSessionReadout?, next: LiveSessionReadout, lastPublishedAt: Date?, now: Date) -> Bool }`

- [ ] **Step 1: Write the failing tests**

Append inside `struct LiveEffortTests`:

```swift
    @Test func builderJoinsEverythingAndKeepsAbsence() throws {
        let zones = try #require(HeartRateZones(birthDate: thirtyYearsOld, on: today, calendar: calendar))
        var effort = EffortAccumulator(); effort.add(zone: 3, seconds: 1800)
        let timer = ActivitySessionState(activity: "Run", at: today)
        let capacity = Capacity(percent: 60, source: .whoop, measuredOn: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: 150, zones: zones, effort: effort,
                                                 capacity: capacity, energyKcal: 210.6, distanceMeters: 1234.9)
        #expect(readout.heartRate == 150)
        #expect(readout.zone == 4)
        #expect(readout.effort == 7.2)
        #expect(readout.calories == 211)
        #expect(readout.distanceMeters == 1235)
        #expect(readout.batteryPercent == 29)
        #expect(readout.capacitySource == "whoop")
        #expect(readout.ceilingMaxZone == 4)
        #expect(readout.ceilingTarget == 10...14)
        #expect(readout.push == .nearLimit)
        #expect(readout.runningSince == today)
    }

    @Test func builderWithoutZonesReportsBeatsOnly() {
        let timer = ActivitySessionState(activity: "Walk", at: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: 120, zones: nil, effort: EffortAccumulator(load: 500),
                                                 capacity: nil, energyKcal: nil, distanceMeters: nil)
        #expect(readout.heartRate == 120)
        #expect(readout.zone == nil)
        #expect(readout.effort == nil)
        #expect(readout.batteryPercent == nil)
        #expect(readout.calories == nil)
        #expect(readout.ceilingMaxZone == nil)
        #expect(readout.push == .onTrack)
    }

    @Test func builderUsesConservativeCeilingWithoutCapacity() throws {
        let zones = try #require(HeartRateZones(birthDate: thirtyYearsOld, on: today, calendar: calendar))
        let timer = ActivitySessionState(activity: "Run", at: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: 175, zones: zones, effort: EffortAccumulator(),
                                                 capacity: nil, energyKcal: nil, distanceMeters: nil)
        #expect(readout.batteryPercent == nil)
        #expect(readout.ceilingMaxZone == 4)
        #expect(readout.push == .overLimit)
    }
```

Append inside `struct LiveSessionReadoutTests`:

```swift
    private func readout(bpm: Int?, effort: Double? = 5, paused: Bool = false, push: PushState = .onTrack) -> LiveSessionReadout {
        var value = LiveSessionReadout(elapsed: 60, runningSince: paused ? nil : start, push: push)
        value.heartRate = bpm; value.effort = effort
        return value
    }

    @Test func throttlePublishesFirstAndOnMeaningfulChange() {
        let now = start.addingTimeInterval(100)
        #expect(LiveActivityThrottle.shouldPublish(previous: nil, next: readout(bpm: 120), lastPublishedAt: nil, now: now))
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 121), lastPublishedAt: now.addingTimeInterval(-2), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 123), lastPublishedAt: now.addingTimeInterval(-2), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: nil), lastPublishedAt: now.addingTimeInterval(-2), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120, push: .nearLimit), lastPublishedAt: now.addingTimeInterval(-1), now: now))
    }

    @Test func throttleFloorsSmallChangesAtTenSeconds() {
        let now = start.addingTimeInterval(100)
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120, effort: 5.0), next: readout(bpm: 120, effort: 5.1), lastPublishedAt: now.addingTimeInterval(-4), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120, effort: 5.0), next: readout(bpm: 120, effort: 5.1), lastPublishedAt: now.addingTimeInterval(-10), now: now))
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120), lastPublishedAt: now.addingTimeInterval(-60), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120, paused: true), lastPublishedAt: now, now: now))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter "LiveEffortTests|LiveSessionReadoutTests" 2>&1 | tail -5`
Expected: compile errors for `LiveReadoutBuilder` and `LiveActivityThrottle`.

- [ ] **Step 3: Write the builder and the throttle**

Append to `LifeOSKit/Sources/Integrations/LiveEffort.swift`:

```swift
/// Joins the recorder's state into the one readout every surface renders.
public enum LiveReadoutBuilder {
    public static func readout(timer: ActivitySessionState, heartRate: Int?, zones: HeartRateZones?,
                               effort: EffortAccumulator, capacity: Capacity?,
                               energyKcal: Double?, distanceMeters: Double?) -> LiveSessionReadout {
        let zone = zones.flatMap { zones in heartRate.map { zones.zone(for: $0) } }
        let ceiling = capacity?.ceiling ?? .conservative
        let push: PushState = zones == nil ? .onTrack : EffortMath.pushState(zone: zone, effort: effort.effort, ceiling: ceiling)
        var readout = LiveSessionReadout(elapsed: timer.accumulated, runningSince: timer.runningSince, push: push)
        readout.heartRate = heartRate
        readout.zone = zone
        readout.calories = energyKcal.map { Int($0.rounded()) }
        readout.distanceMeters = distanceMeters.map { Int($0.rounded()) }
        readout.capacitySource = capacity?.source.rawValue
        if zones != nil {
            readout.effort = (effort.effort * 10).rounded() / 10
            readout.ceilingMaxZone = ceiling.maxZone
            readout.ceilingTarget = ceiling.targetEffort
            readout.batteryPercent = capacity.map {
                EffortMath.batteryRemaining(capacity: $0.percent, effort: effort.effort, ceiling: ceiling)
            }
        }
        return readout
    }
}
```

Append to `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift`:

```swift
/// Decides whether a new readout is worth an ActivityKit update. The sensor
/// streams every second; the lock screen does not need to.
public enum LiveActivityThrottle {
    public static let heartRateStep = 3
    public static let floor: TimeInterval = 10

    public static func shouldPublish(previous: LiveSessionReadout?, next: LiveSessionReadout,
                                     lastPublishedAt: Date?, now: Date) -> Bool {
        guard let previous, let lastPublishedAt else { return true }
        if previous == next { return false }
        if previous.isPaused != next.isPaused { return true }
        if previous.push != next.push { return true }
        switch (previous.heartRate, next.heartRate) {
        case let (old?, new?) where abs(old - new) >= heartRateStep: return true
        case (nil, .some), (.some, nil): return true
        default: break
        }
        return now.timeIntervalSince(lastPublishedAt) >= floor
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter "LiveEffortTests|LiveSessionReadoutTests" 2>&1 | tail -3`
Expected: all pass. The builder test expects effort 7.2 from 1800 s in zone 3 (load 630, `21 * (1 - exp(-0.42))` is 7.19) and battery 29 (`60 * (1 - 7.19 / 14)` is 29.2).

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Integrations/LiveEffort.swift LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift LifeOSKit/Tests
git commit -m "feat(effort): build the readout and throttle its publishing

One builder joins timer, beats, zones, effort and capacity into the
readout; one pure decision keeps Live Activity updates to meaningful
changes or a ten second floor."
```

---

### Task 7: Recorder computes the readout and keeps it in the draft

**Files:**
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`
- Modify: `LIfeOS/App/Surfaces/WorkoutLiveActivityController.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift`
- Modify: `LIfeOS/App/RootView.swift:698-699`

**Interfaces:**
- Consumes: everything from Tasks 2 to 6; `ProfileStore.load().birthDate` (`LIfeOS/Features/Onboarding/Model/ProfilePhotoStore.swift`); `MetricsStore.metrics(from:to:)`.
- Produces on `ActivityRecorder`: `private(set) var readout: LiveSessionReadout?`, `private(set) var capacity: Capacity?`, `var zonesAvailable: Bool`, `var birthDate: () -> Date?`, `var whoopConnected: () -> Bool`.
- Produces on `WorkoutLiveActivityController`: `func sync(_ readout: LiveSessionReadout, timer: ActivitySessionState, icon: String)`.

- [ ] **Step 1: Extend the checks harness (the failing test)**

In `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift`, after the line `let recorder = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)` insert:

```swift
            recorder.birthDate = { Calendar.current.date(from: DateComponents(year: 1996, month: 6, day: 1)) }
            _ = try MetricsStore(context: context).upsert(date: .now) { $0.whoopRecoveryPct = 80; $0.whoopSleepPerformancePct = 90 }
```

After `check(recorder.isRunning && recorder.timer != nil, "Timer starts without Health access")` insert:

```swift
            check(recorder.capacity?.percent == 82 && recorder.readout?.batteryPercent == 82, "Capacity comes from today's recovery at start")
            let base = Date.now.addingTimeInterval(-30)
            for second in 0..<30 { recorder.sensor.onReading?(140, base.addingTimeInterval(Double(second))) }
            check(recorder.readout?.heartRate == 140 && recorder.readout?.zone == 3 && (recorder.readout?.effort ?? 0) > 0, "Readings yield zone and effort")
```

After `check(restored.timer?.id == id && restored.isRunning && !restored.busy, "Timer-only draft restores without Health recovery")` insert:

```swift
            check(restored.capacity?.percent == 82 && (restored.readout?.effort ?? 0) > 0, "Draft restores capacity and effort")
```

Note `restored` is created without `birthDate`; add `restored.birthDate = recorder.birthDate` on the line right after `let restored = ActivityRecorder(...)` and before `restored.attach(context)`.

- [ ] **Step 2: Build to verify it fails**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build 2>&1 | grep -E "error:|BUILD" | head`
Expected: `error: value of type 'ActivityRecorder' has no member 'birthDate'`.

- [ ] **Step 3: Change the recorder**

In `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`:

Add after `import Integrations`:
```swift
import AppSurfaces
```

Replace the property block from `private(set) var heartRate: Double?` through `var onSaved: (() -> Void)?` and the `Draft` struct and `init` with:

```swift
    private(set) var heartRate: Double?
    private(set) var heartRateDate: Date?
    private(set) var capacity: Capacity?
    private(set) var readout: LiveSessionReadout?
    var error: String?
    var notice: String?
    let sensor = LiveHeartRateSensor()
    /// Injected so previews and checks can fix an age without a profile.
    var birthDate: () -> Date? = { ProfileStore.load().birthDate }
    /// Whether the WHOOP cloud account is connected; decides auto-pairing.
    var whoopConnected: () -> Bool = { false }
    private var zones: HeartRateZones?
    private var effort = EffortAccumulator()
    private var lastReadingAt: Date?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var context: ModelContext?
    private let defaults: UserDefaults
    private var active = true
    private let liveActivity = WorkoutLiveActivityController()
    private let liveActivitiesEnabled: Bool
    private var collectionEnded = false
    private var finishing = false
    private var recordingHealth = false
    private static let draftKey = "activeWorkoutDraft"
    var onSaved: (() -> Void)?
    var zonesAvailable: Bool { zones != nil }

    private struct Draft: Codable {
        var timer: ActivitySessionState
        var healthSaved: Bool
        var recordsHealth: Bool?
        var energy: Double?
        var distance: Double?
        var capacity: Capacity?
        var effortLoad: Double?
    }

    init(defaults: UserDefaults = .currentAccount, liveActivitiesEnabled: Bool = true) {
        self.defaults = defaults
        self.liveActivitiesEnabled = liveActivitiesEnabled
        super.init()
        sensor.onReading = { [weak self] bpm, date in self?.receiveHeartRate(bpm, at: date) }
    }
```

In `attach(_:)`, replace
```swift
        timer = draft.timer; healthSaved = draft.healthSaved; energy = draft.energy; distance = draft.distance
        selection = RecordedActivity(rawValue: draft.timer.activity) ?? .other
        if liveActivitiesEnabled { liveActivity.sync(draft.timer, icon: selection.icon) }
```
with
```swift
        timer = draft.timer; healthSaved = draft.healthSaved; energy = draft.energy; distance = draft.distance
        capacity = draft.capacity; effort = EffortAccumulator(load: draft.effortLoad ?? 0)
        zones = HeartRateZones(birthDate: birthDate())
        selection = RecordedActivity(rawValue: draft.timer.activity) ?? .other
        refreshReadout()
```

In `start()`, replace the line `busy = true; error = nil; saved = false; healthSaved = false; collectionEnded = false` with:
```swift
        busy = true; error = nil; saved = false; healthSaved = false; collectionEnded = false
        zones = HeartRateZones(birthDate: birthDate())
        capacity = loadCapacity()
        effort = EffortAccumulator(); lastReadingAt = nil
        sensor.prepareForSession(whoopConnected: whoopConnected())
```
(`prepareForSession` is added in Task 12. Until then, add a one-line stub to `LiveHeartRateSensor`: `func prepareForSession(whoopConnected: Bool) {}` so this task builds. Task 12 replaces the stub.)

In `togglePause()`, replace the body with:
```swift
        guard !busy else { return }
        if isRunning { timer?.pause(); session?.pause() }
        else if isPaused { timer?.resume(); session?.resume(); lastReadingAt = nil }
        persist()
```

In `discard()`, after `energy = nil; distance = nil; heartRate = nil; heartRateDate = nil` add:
```swift
        capacity = nil; readout = nil; effort = EffortAccumulator(); lastReadingAt = nil; zones = nil
```

Replace `persist()` with:
```swift
    private func persist() {
        refreshReadout()
        guard active, let timer,
              let data = try? JSONEncoder().encode(Draft(timer: timer, healthSaved: healthSaved, recordsHealth: recordingHealth,
                                                         energy: energy, distance: distance, capacity: capacity, effortLoad: effort.load)) else { return }
        defaults.set(data, forKey: Self.draftKey)
        if liveActivitiesEnabled, let readout { liveActivity.sync(readout, timer: timer, icon: selection.icon) }
    }
    private func refreshReadout() {
        guard let timer else { readout = nil; return }
        readout = LiveReadoutBuilder.readout(timer: timer, heartRate: heartRate.map { Int($0) }, zones: zones, effort: effort,
                                             capacity: capacity, energyKcal: energy, distanceMeters: distance)
    }
    /// Today's row, or yesterday's while today has not synced. A week of
    /// rows behind it gives the Health path its HRV baseline.
    private func loadCapacity() -> Capacity? {
        guard let context else { return nil }
        let rows = (try? MetricsStore(context: context).metrics(from: .now.addingTimeInterval(-9 * 86400), to: .now)) ?? []
        let days = rows.map {
            RecoveryDay(date: $0.date, whoopRecoveryPct: $0.whoopRecoveryPct, whoopIsCalibrating: $0.whoopRecoveryIsCalibrating,
                        sleepPerformancePct: $0.whoopSleepPerformancePct, hrvMs: $0.hrvMs, sleepMinutes: $0.sleepMinutes)
        }
        return CapacityMath.capacity(days: days, now: .now)
    }
```

Replace `receiveHeartRate` with:
```swift
    private func receiveHeartRate(_ bpm: Int, at date: Date) {
        guard active, isRunning else { return }
        heartRate = Double(bpm); heartRateDate = date
        if let zones {
            effort.add(zone: zones.zone(for: bpm), seconds: EffortAccumulator.credit(previous: lastReadingAt, at: date))
        }
        lastReadingAt = date
        persist()
        guard let builder, healthStore.authorizationStatus(for: .quantityType(forIdentifier: .heartRate)!) == .sharingAuthorized else { return }
        let sample = HKQuantitySample(type: .quantityType(forIdentifier: .heartRate)!,
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(bpm)), start: date, end: date)
        builder.add([sample]) { _, _ in }
    }
```

In the `workoutBuilder(_:didCollectDataOf:)` heart-rate case, the builder can also deliver beats (from a HealthKit-paired sensor). Replace that case with:
```swift
                case HKQuantityTypeIdentifier.heartRate.rawValue:
                    if let bpm = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                       let date = stats.mostRecentQuantityDateInterval()?.end, date != self.heartRateDate {
                        self.heartRate = bpm; self.heartRateDate = date
                        if let zones = self.zones {
                            self.effort.add(zone: zones.zone(for: Int(bpm)), seconds: EffortAccumulator.credit(previous: self.lastReadingAt, at: date))
                        }
                        self.lastReadingAt = date
                    }
```

Replace `LIfeOS/App/Surfaces/WorkoutLiveActivityController.swift` entirely with:

```swift
import ActivityKit
import AppSurfaces
import Integrations
import Foundation

@MainActor
final class WorkoutLiveActivityController {
    private var current: Activity<WorkoutActivityAttributes>?
    private var lastState: LiveSessionReadout?
    private var lastPublishedAt: Date?
    private var updates: Task<Void, Never>?

    func sync(_ readout: LiveSessionReadout, timer: ActivitySessionState, icon: String) {
        guard timer.phase != .finished else { end(); return }
        if current == nil {
            current = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.sessionID == timer.id }
        }
        let now = Date.now
        guard current == nil || LiveActivityThrottle.shouldPublish(previous: lastState, next: readout, lastPublishedAt: lastPublishedAt, now: now) else { return }
        lastState = readout; lastPublishedAt = now
        let content = ActivityContent(state: readout, staleDate: now.addingTimeInterval(8 * 3600))
        if let current {
            let preceding = updates
            updates = Task { await preceding?.value; await current.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            current = try? Activity.request(attributes: WorkoutActivityAttributes(sessionID: timer.id,
                name: timer.activity, icon: icon), content: content, pushType: nil)
        }
    }
    func end() {
        guard let current else { return }
        let preceding = updates
        updates = Task { await preceding?.value; await current.end(nil, dismissalPolicy: .immediate) }
        self.current = nil; lastState = nil; lastPublishedAt = nil
    }
    static func endAll() {
        let existing = Activity<WorkoutActivityAttributes>.activities
        Task { for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
}
```

In `LIfeOS/App/RootView.swift`, after `recorder.attach(context)` (line 698) add:
```swift
        recorder.whoopConnected = { [whoop] in whoop.isConnected }
```

Add the temporary stub to `LIfeOS/Features/Activity/ViewModel/LiveHeartRateSensor.swift` inside the class:
```swift
    func prepareForSession(whoopConnected: Bool) {}
```

- [ ] **Step 4: Build and run the checks**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build 2>&1 | grep -E "error:|BUILD" | head`
Expected: `** BUILD SUCCEEDED **`.

Run the checks page on the simulator:
```bash
UDID=$(xcrun simctl list devices available | grep "iPhone 17 (" | head -1 | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$UDID" 2>/dev/null; open -a Simulator --args -CurrentDeviceUDID "$UDID"
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/LIfeOS.app" | head -1)
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.shivvyas.lifeos --page=checks
sleep 8
DOCS=$(xcrun simctl get_app_container "$UDID" com.shivvyas.lifeos data)/Documents
cat "$DOCS/recorder-checks.txt"
```
(Confirm the bundle id with `grep -A1 PRODUCT_BUNDLE_IDENTIFIER LIfeOS.xcodeproj/project.pbxproj | head -3` and adjust if it differs. The `--page=checks` route is only honoured by the design preview entry point; check `LIfeOS/App/AppShell.swift` or `LIfeOSApp.swift` for the `--design-preview` launch argument that selects `HealthActivityDesignPreview` and pass it too, for example `--design-preview --page=checks`.)
Expected: every line begins with `PASS`, including the three new ones.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Activity/ViewModel LIfeOS/App/Surfaces/WorkoutLiveActivityController.swift LIfeOS/App/RootView.swift
git commit -m "feat(activity): recorder computes a live readout

Zones from the profile birth date, capacity from today's recovery at
start, effort accrued per reading, and one readout handed to a throttled
Live Activity controller. Capacity and effort survive in the draft."
```

---

### Task 8: Push-state tints in the design system

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/Tokens.swift`

**Interfaces:**
- Produces: `LifeOSTokens.pushEasy`, `LifeOSTokens.pushNear`, `LifeOSTokens.pushOver` (`Color`), `LifeOSTokens.liveGradientTop`, `LifeOSTokens.liveGradientBottom`.

- [ ] **Step 1: Add the tokens**

In `LifeOSKit/Sources/DesignSystem/Tokens.swift`, inside `public enum LifeOSTokens` after `public static let accent = ...` add:

```swift
    /// Live session push states. Identical in both schemes because they sit
    /// on the live gradient, which is also the same in both.
    public static let pushEasy = Color(red: 0.20, green: 0.72, blue: 0.45)
    public static let pushNear = Color(red: 0.96, green: 0.65, blue: 0.14)
    public static let pushOver = Color(red: 0.90, green: 0.27, blue: 0.23)

    /// The live session gradient: the recovery blue at the top, near white
    /// at the bottom, on the lock screen and the in-session hero alike.
    public static let liveGradientTop = ModuleHue.recovery.top
    public static let liveGradientBottom = Color(white: 0.97)
```

- [ ] **Step 2: Build the package**

Run: `cd LifeOSKit && swift build 2>&1 | tail -2`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/Tokens.swift
git commit -m "feat(design): push-state tints and the live gradient"
```

---

### Task 9: Live Activity lock screen and Dynamic Island

**Files:**
- Modify: `LIfeOS.xcodeproj/project.pbxproj` (link `DesignSystem` into `AlmanacWidgets`)
- Modify: `AlmanacWidgets/WorkoutLiveActivity.swift`

**Interfaces:**
- Consumes: `LiveSessionReadout`, `PushState.headline`, `LifeOSTokens.push*`, `LifeOSTokens.liveGradient*`, `SurfaceRoute.activity.url`.

- [ ] **Step 1: Link DesignSystem into the widget target**

Run this script from the worktree root. It adds a build file, a product dependency and the two references, using fixed 24-character ids that do not collide with anything in the file:

```bash
python3 - <<'EOF'
import re
p = "LIfeOS.xcodeproj/project.pbxproj"
s = open(p).read()
assert "A1B2C3D4E5F60718293A4B5C" not in s
s = s.replace(
    "\t\t57DCE402662FEC521A28FB42 /* AppSurfaces in Frameworks */ = {isa = PBXBuildFile; productRef = D04A72741F9CF213015F7725 /* AppSurfaces */; };",
    "\t\t57DCE402662FEC521A28FB42 /* AppSurfaces in Frameworks */ = {isa = PBXBuildFile; productRef = D04A72741F9CF213015F7725 /* AppSurfaces */; };\n"
    "\t\tA1B2C3D4E5F60718293A4B5C /* DesignSystem in Frameworks */ = {isa = PBXBuildFile; productRef = A1B2C3D4E5F60718293A4B5D /* DesignSystem */; };", 1)
s = s.replace(
    "\t\t\t\t57DCE402662FEC521A28FB42 /* AppSurfaces in Frameworks */,\n",
    "\t\t\t\t57DCE402662FEC521A28FB42 /* AppSurfaces in Frameworks */,\n\t\t\t\tA1B2C3D4E5F60718293A4B5C /* DesignSystem in Frameworks */,\n", 1)
s = s.replace(
    "\t\t\tname = AlmanacWidgets;\n\t\t\tpackageProductDependencies = (\n\t\t\t\tD04A72741F9CF213015F7725 /* AppSurfaces */,\n",
    "\t\t\tname = AlmanacWidgets;\n\t\t\tpackageProductDependencies = (\n\t\t\t\tD04A72741F9CF213015F7725 /* AppSurfaces */,\n\t\t\t\tA1B2C3D4E5F60718293A4B5D /* DesignSystem */,\n", 1)
s = s.replace(
    "\t\tD04A72741F9CF213015F7725 /* AppSurfaces */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = AppSurfaces;\n\t\t};",
    "\t\tD04A72741F9CF213015F7725 /* AppSurfaces */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = AppSurfaces;\n\t\t};\n"
    "\t\tA1B2C3D4E5F60718293A4B5D /* DesignSystem */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = DesignSystem;\n\t\t};", 1)
assert s.count("A1B2C3D4E5F60718293A4B5C") == 2 and s.count("A1B2C3D4E5F60718293A4B5D") == 3, "an anchor did not match; inspect the pbxproj"
open(p, "w").write(s)
EOF
```

Verify the frameworks phase you touched belongs to `AlmanacWidgets`: `grep -n "912B9AAFCAFE79E2C226F85F" LIfeOS.xcodeproj/project.pbxproj` should show it both in the `AlmanacWidgets` target's `buildPhases` and in the phase that now lists `DesignSystem in Frameworks`. If the `57DCE402...` build file sits in a different phase than `912B9AAF...`, move the inserted line to the `912B9AAF...` phase.

- [ ] **Step 2: Rewrite the Live Activity**

Replace `AlmanacWidgets/WorkoutLiveActivity.swift` with:

```swift
import ActivityKit
import SwiftUI
import WidgetKit
import AppSurfaces
import DesignSystem

/// The lock screen and Dynamic Island for a running activity. Widget
/// extensions cannot render materials, so the "glass" tiles are translucent
/// white over the live gradient with a hairline edge.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(name: context.attributes.name, icon: context.attributes.icon, readout: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(SurfaceRoute.activity.url)
        } dynamicIsland: { context in
            let readout = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.name, systemImage: context.attributes.icon)
                        .font(.headline).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutTimer(readout: readout).font(.system(.title2, design: .rounded, weight: .bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 14) {
                            IslandReading(symbol: "heart.fill", value: readout.heartRate.map(String.init), unit: readout.zone.map { "Z\($0)" }, tint: readout.push.tint)
                            IslandReading(symbol: "bolt.fill", value: readout.effort.map { String(format: "%.1f", $0) }, unit: "est", tint: .white)
                            IslandReading(symbol: "flame.fill", value: readout.calories.map(String.init), unit: "kcal", tint: .white)
                            IslandReading(symbol: "battery.75percent", value: readout.batteryPercent.map { "\($0)%" }, unit: "left", tint: .white)
                        }
                        HStack {
                            Text(readout.isPaused ? "Paused" : readout.push.headline).foregroundStyle(.secondary)
                            Spacer()
                            Link("Open activity", destination: SurfaceRoute.activity.url).foregroundStyle(readout.push.tint)
                        }.font(.subheadline)
                    }.padding(.top, 6)
                }
            } compactLeading: {
                if let bpm = readout.heartRate {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.caption2)
                        Text("\(bpm)").font(.caption.monospacedDigit().weight(.semibold))
                    }.foregroundStyle(readout.push.tint)
                } else {
                    Image(systemName: context.attributes.icon).foregroundStyle(readout.push.tint)
                }
            } compactTrailing: {
                WorkoutTimer(readout: readout).font(.caption.monospacedDigit()).frame(width: 48)
            } minimal: {
                if let zone = readout.zone {
                    Text("\(zone)").font(.caption2.bold()).foregroundStyle(.black)
                        .frame(width: 18, height: 18).background(readout.push.tint, in: Circle())
                } else {
                    Image(systemName: readout.isPaused ? "pause.fill" : context.attributes.icon).foregroundStyle(readout.push.tint)
                }
            }
            .widgetURL(SurfaceRoute.activity.url)
            .keylineTint(readout.push.tint)
        }
    }
}

private struct LockScreenView: View {
    let name: String
    let icon: String
    let readout: LiveSessionReadout

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44).background(.white.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.headline)
                    Text(readout.isPaused ? "Paused" : readout.push.headline).font(.caption)
                        .foregroundStyle(readout.push == .overLimit || readout.push == .nearLimit ? readout.push.tint : .white.opacity(0.85))
                }
                Spacer(minLength: 6)
                WorkoutTimer(readout: readout).font(.system(.title, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
            .foregroundStyle(.white)
            HStack(spacing: 8) {
                Tile(eyebrow: readout.zone.map { "Z\($0)" } ?? "BPM", value: readout.heartRate.map(String.init), symbol: "heart.fill")
                Tile(eyebrow: readout.ceilingTarget.map { "EST of \(Int($0.upperBound))" } ?? "EST", value: readout.effort.map { String(format: "%.1f", $0) }, symbol: "bolt.fill")
                Tile(eyebrow: "KCAL", value: readout.calories.map(String.init), symbol: "flame.fill")
                Tile(eyebrow: "LEFT", value: readout.batteryPercent.map { "\($0)%" }, symbol: "battery.75percent", ring: readout.batteryPercent)
            }
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(colors: [LifeOSTokens.liveGradientTop, LifeOSTokens.liveGradientBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.2), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            }
        }
    }
}

private struct Tile: View {
    let eyebrow: String
    let value: String?
    let symbol: String
    var ring: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2)
                Text(eyebrow).font(.system(size: 10, weight: .semibold)).tracking(0.4)
            }.opacity(0.75)
            HStack(spacing: 6) {
                Text(value ?? "\u{2014}").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let ring {
                    Circle().trim(from: 0, to: CGFloat(ring) / 100).stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 14, height: 14)
                        .background(Circle().stroke(.white.opacity(0.25), lineWidth: 3))
                }
            }
        }
        .foregroundStyle(Color(white: 0.12))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.5))
        .privacySensitive()
    }
}

private struct IslandReading: View {
    let symbol: String
    let value: String?
    let unit: String?
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(tint)
            Text(value ?? "\u{2014}").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
            if let unit, value != nil { Text(unit).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

private struct WorkoutTimer: View {
    let readout: LiveSessionReadout
    var body: some View {
        if let anchor = readout.timerAnchor {
            Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
                .monospacedDigit().contentTransition(.numericText()).privacySensitive()
        } else {
            Text(Duration.seconds(readout.elapsed).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit().privacySensitive()
        }
    }
}

extension PushState {
    var tint: Color {
        switch self {
        case .easy, .onTrack: LifeOSTokens.pushEasy
        case .nearLimit: LifeOSTokens.pushNear
        case .overLimit: LifeOSTokens.pushOver
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build 2>&1 | grep -E "error:|BUILD" | head`
Expected: `** BUILD SUCCEEDED **`. If `DesignSystem` is reported missing for the widget target, re-check Step 1's phase mapping.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS.xcodeproj/project.pbxproj AlmanacWidgets/WorkoutLiveActivity.swift
git commit -m "feat(widgets): gradient Live Activity with live readings

Blue to white gradient, translucent tiles for beats and zone, estimated
effort, calories and battery, a push-state headline, and a Dynamic
Island that shows beats compact and every reading expanded. The widget
target now links DesignSystem instead of hardcoding orange."
```

---

### Task 10: `SessionHUD`

**Files:**
- Create: `LIfeOS/Features/Activity/View/SessionHUD.swift`

**Interfaces:**
- Consumes: `LiveSessionReadout`, `PushState`, `RecordedActivity`, `LifeOSTokens`, `LifeOSType`.
- Produces: `struct SessionHUD: View { init(readout: LiveSessionReadout, activity: RecordedActivity, zonesAvailable: Bool, isExpanded: Binding<Bool>) }`.

- [ ] **Step 1: Write the view**

Create `LIfeOS/Features/Activity/View/SessionHUD.swift`:

```swift
import SwiftUI
import AppSurfaces
import DesignSystem

/// One glass capsule with the readings that matter right now. Tap to expand
/// into the ceiling line and the slower numbers. Adapts to the activity:
/// distance for movement, a reps slot for strength, no effort talk for yoga.
struct SessionHUD: View {
    let readout: LiveSessionReadout
    let activity: RecordedActivity
    let zonesAvailable: Bool
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) private var scheme
    @Namespace private var glass

    private var showsEffort: Bool { activity != .yoga && zonesAvailable }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        timer.frame(minWidth: 62, alignment: .leading)
                        reading(symbol: "heart.fill", value: readout.heartRate.map(String.init), chip: readout.zone.map { "Z\($0)" }, tint: readout.push.tint)
                        if showsEffort {
                            reading(symbol: "bolt.fill", value: readout.effort.map { String(format: "%.1f", $0) }, chip: "est", tint: nil)
                            reading(symbol: "battery.75percent", value: readout.batteryPercent.map { "\($0)%" }, chip: nil, tint: nil)
                        }
                        if activity == .strength {
                            reading(symbol: "repeat", value: nil, chip: "reps", tint: nil)
                        }
                    }
                    if isExpanded { expanded }
                }
                .padding(.horizontal, 18).padding(.vertical, isExpanded ? 14 : 10)
                .frame(minHeight: 52)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(readout.push.tint.opacity(0.18)).interactive(),
                         in: isExpanded ? AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)) : AnyShape(Capsule()))
            .glassEffectID("hud", in: glass)
        }
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityLabel(isExpanded ? "" : summary)
        .accessibilityHint(isExpanded ? "" : "Double tap for today's ceiling and calories")
    }

    private var timer: some View {
        Group {
            if let anchor = readout.timerAnchor {
                Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
            } else {
                Text(Duration.seconds(readout.elapsed).formatted(.time(pattern: .minuteSecond)))
            }
        }
        .font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1)
    }

    private func reading(symbol: String, value: String?, chip: String?, tint: Color?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint ?? LifeOSTokens.secondaryText.resolve(scheme))
            Text(value ?? "\u{2014}").font(.headline).monospacedDigit().frame(minWidth: 30, alignment: .leading)
            if let chip {
                Text(chip).font(LifeOSType.eyebrow).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }.lineLimit(1)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ceilingLine).font(LifeOSType.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            HStack(spacing: 16) {
                reading(symbol: "flame.fill", value: readout.calories.map(String.init), chip: "kcal", tint: nil)
                if [.walk, .run, .cycle].contains(activity) {
                    reading(symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                            value: readout.distanceMeters.map { String(format: "%.2f", Double($0) / 1000) }, chip: "km", tint: nil)
                }
                if readout.push == .overLimit { Text("Over your target").font(LifeOSType.label).foregroundStyle(LifeOSTokens.pushNear) }
            }
        }
    }

    private var ceilingLine: String {
        if activity == .yoga { return "Recovery session" }
        guard zonesAvailable else { return "Add your birth date in Profile for zones and effort." }
        let source = switch readout.capacitySource {
            case "whoop": "WHOOP recovery"
            case "health": "Apple Health"
            default: "Battery unknown"
        }
        guard let zone = readout.ceilingMaxZone, let target = readout.ceilingTarget else { return source }
        return "Up to zone \(zone) today · target \(Int(target.lowerBound)) to \(Int(target.upperBound)) · \(source)"
    }

    private var summary: String {
        var parts = ["Elapsed \(Duration.seconds(readout.elapsed).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))"]
        if let bpm = readout.heartRate { parts.append("heart rate \(bpm)") }
        if let zone = readout.zone { parts.append("zone \(zone)") }
        if showsEffort, let effort = readout.effort { parts.append(String(format: "effort %.1f estimated", effort)) }
        if showsEffort, let battery = readout.batteryPercent { parts.append("battery \(battery) percent") }
        return parts.joined(separator: ", ")
    }
}

extension PushState {
    var tint: Color {
        switch self {
        case .easy, .onTrack: LifeOSTokens.pushEasy
        case .nearLimit: LifeOSTokens.pushNear
        case .overLimit: LifeOSTokens.pushOver
        }
    }
}

#Preview("Collapsed and expanded") {
    struct Host: View {
        @State private var expanded = false
        @State private var expandedTwo = true
        var readout: LiveSessionReadout {
            var value = LiveSessionReadout(elapsed: 724, runningSince: .now, push: .nearLimit)
            value.heartRate = 152; value.zone = 4; value.effort = 9.3; value.calories = 210
            value.batteryPercent = 62; value.capacitySource = "whoop"; value.ceilingMaxZone = 4; value.ceilingTarget = 10...14
            return value
        }
        var body: some View {
            ZStack {
                LinearGradient(colors: [LifeOSTokens.liveGradientTop, LifeOSTokens.liveGradientBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 24) {
                    SessionHUD(readout: readout, activity: .run, zonesAvailable: true, isExpanded: $expanded)
                    SessionHUD(readout: readout, activity: .strength, zonesAvailable: true, isExpanded: $expandedTwo)
                    SessionHUD(readout: LiveSessionReadout(elapsed: 30, runningSince: nil, push: .onTrack), activity: .yoga, zonesAvailable: false, isExpanded: $expanded)
                }.padding()
            }
        }
    }
    return Host()
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build 2>&1 | grep -E "error:|BUILD" | head`
Expected: `** BUILD SUCCEEDED **`. If `AnyShape` with `glassEffect` fails to type-check, use two explicit modifiers behind `if isExpanded` on the label instead.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Activity/View/SessionHUD.swift
git commit -m "feat(activity): a glass session HUD

One Liquid Glass capsule with timer, beats and zone, estimated effort
and battery, tinted by push state. Tap expands into the ceiling line,
calories and distance. Strength reserves a reps slot; yoga drops effort."
```

---

### Task 11: In-session screen with the gradient hero

**Files:**
- Modify: `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`

**Interfaces:**
- Consumes: `SessionHUD`, `ActivityRecorder.readout`, `ActivityRecorder.zonesAvailable`, `ActivityRecorder.capacity`.

- [ ] **Step 1: Restyle the in-session state**

In `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`:

Add `import AppSurfaces` after `import Integrations`, and `@State private var hudExpanded = false` after `@State private var confirmDiscard = false`.

Replace the `ScrollView { VStack(alignment: .leading, spacing: 22) { ... } ... }` body's first three lines
```swift
                    AccountPageHeading(...)
                    timerCard
                    if !model.hasSession && !model.saved { activityPicker }
                    if model.hasSession { liveReadings }
```
with
```swift
                    if model.hasSession, let readout = model.readout {
                        liveHero(readout)
                        liveTiles(readout)
                    } else {
                        AccountPageHeading(title: model.saved ? "Time well spent." : "Make time to move.",
                            detail: model.saved ? (model.healthSaved ? "Saved to Almanac and Apple Health." : "Saved to your Almanac account on this device.") : "One activity. Your own pace.")
                        timerCard
                        if !model.saved { activityPicker }
                    }
```

Change `.background(LifeOSTokens.canvas.resolve(scheme))` on the `ScrollView` to:
```swift
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
                    if model.hasSession {
                        LinearGradient(colors: [scheme == .dark ? ModuleHue.recovery.darkTop : LifeOSTokens.liveGradientTop,
                                                LifeOSTokens.canvas.resolve(scheme)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 380).ignoresSafeArea(edges: .top)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
```

Add these two views after `timerCard`:

```swift
    private func liveHero(_ readout: LiveSessionReadout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.selection.rawValue, systemImage: model.selection.icon).font(LifeOSType.rowTitle)
                Spacer()
                Text(readout.isPaused ? "Paused" : readout.push.headline).font(LifeOSType.label)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(duration(model.timer?.elapsed(at: timeline.date) ?? 0))
                    .font(.system(size: 72, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .accessibilityLabel("Elapsed time, \(duration(model.timer?.elapsed(at: timeline.date) ?? 0))")
            }
            Text("Elapsed time").font(LifeOSType.caption).opacity(0.85)
            SessionHUD(readout: readout, activity: model.selection, zonesAvailable: model.zonesAvailable, isExpanded: $hudExpanded)
                .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private func liveTiles(_ readout: LiveSessionReadout) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = model.isRunning && model.heartRateDate.map { timeline.date.timeIntervalSince($0) < 15 } == true
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                glassTile(icon: "heart.fill", label: readout.zone.map { "Heart rate · Z\($0)" } ?? "Heart rate",
                          value: fresh ? readout.heartRate.map(String.init) : nil, unit: "bpm",
                          caption: fresh ? "Live sensor reading" : model.isPaused ? "Activity paused" : model.sensor.status)
                if model.zonesAvailable, model.selection != .yoga {
                    glassTile(icon: "bolt.fill", label: "Effort, estimated", value: readout.effort.map { String(format: "%.1f", $0) },
                              unit: readout.ceilingTarget.map { "of \(Int($0.upperBound))" },
                              caption: capacityCaption(readout))
                }
                glassTile(icon: "flame.fill", label: "Calories", value: readout.calories.map(String.init), unit: "kcal",
                          caption: readout.calories == nil ? "No energy reading" : "From Apple Health")
                if [.walk, .run, .cycle].contains(model.selection) {
                    glassTile(icon: "point.bottomleft.forward.to.point.topright.scurvepath", label: "Distance",
                              value: readout.distanceMeters.map { String(format: "%.2f", Double($0) / 1000) }, unit: "km",
                              caption: readout.distanceMeters == nil ? "No distance reading" : "From Apple Health")
                }
                if !model.zonesAvailable {
                    Text("Add your birth date in Profile for zones, effort and battery.")
                        .font(LifeOSType.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func capacityCaption(_ readout: LiveSessionReadout) -> String {
        switch readout.capacitySource {
        case "whoop": "Battery \(readout.batteryPercent.map { "\($0)%" } ?? "\u{2014}") · WHOOP recovery"
        case "health": "Battery \(readout.batteryPercent.map { "\($0)%" } ?? "\u{2014}") · Apple Health"
        default: "Battery unknown · cautious target"
        }
    }

    private func glassTile(icon: String, label: String, value: String?, unit: String?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(label, systemImage: icon).font(LifeOSType.label).opacity(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "\u{2014}").font(.title.bold()).monospacedDigit()
                if let unit, value != nil { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }.lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption.weight(.medium)).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
```

Delete the old `liveReadings` view. Leave `controls`, `connections`, `sensorSheet`, `duration` as they are. In `.navigationTitle(...)`, keep `"Activity"` while a session runs.

- [ ] **Step 2: Add a live fixture to the design preview**

In `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`, replace
```swift
            else if page == "activity" { BeginActivityScreen(model: fixture.recorder) }
```
with
```swift
            else if page == "activity" {
                BeginActivityScreen(model: fixture.recorder)
                    .task {
                        guard ProcessInfo.processInfo.arguments.contains("--live"), !fixture.recorder.hasSession else { return }
                        fixture.recorder.selection = ProcessInfo.processInfo.arguments.contains("--strength") ? .strength : .run
                        await fixture.recorder.start()
                        let start = Date.now.addingTimeInterval(-724)
                        for second in stride(from: 0, to: 720, by: 2) {
                            fixture.recorder.sensor.onReading?(second < 120 ? 118 : second < 480 ? 146 : 156, start.addingTimeInterval(Double(second)))
                        }
                        fixture.recorder.sensor.onReading?(152, .now)
                    }
            }
```
and in `HealthActivityFixture.init()` after `recorder.saveToHealth = false` add:
```swift
        recorder.birthDate = { Calendar.current.date(from: DateComponents(year: 1996, month: 6, day: 1)) }
        _ = try? MetricsStore(context: container.mainContext).upsert(date: .now) { $0.whoopRecoveryPct = 82; $0.whoopSleepPerformancePct = 89 }
```

- [ ] **Step 3: Build and capture**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

Capture (the launch argument that selects the design preview is the one `HealthActivityDesignPreview` is mounted under; find it with `grep -rn "design-preview\|HealthActivityDesignPreview()" LIfeOS/App | head`):
```bash
mkdir -p docs/design/live-session
UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro (" | head -1 | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$UDID" 2>/dev/null; open -a Simulator --args -CurrentDeviceUDID "$UDID"
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/LIfeOS.app" | head -1)
xcrun simctl install "$UDID" "$APP"
for variant in "" "--dark" "--strength"; do
  xcrun simctl terminate "$UDID" com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch "$UDID" com.shivvyas.lifeos --design-preview --page=activity --live $variant
  sleep 6
  xcrun simctl io "$UDID" screenshot "docs/design/live-session/session-iphone${variant:+-${variant#--}}.png"
done
```
Open each capture with the Read tool and check: the hero is blue fading into the canvas, the timer reads about 12:04, the HUD shows 152 bpm Z4, an effort of about 3.4 (twelve minutes across zones 2 to 4), a battery of about 66%, and the tiles read as glass. Fix layout issues before moving on.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Activity/View/BeginActivityScreen.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift docs/design/live-session
git commit -m "feat(activity): gradient hero and glass tiles while a session runs

The running state of Begin Activity puts the timer in a blue field with
the session HUD beneath it and the readings as Liquid Glass tiles on the
canvas. The pre-session picker keeps the warm canvas. A --live preview
fixture drives a twelve minute run for captures."
```

---

### Task 12: Sensor auto-connect

**Files:**
- Create: `LifeOSKit/Sources/Integrations/WhoopAutoPair.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/LiveHeartRateSensor.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`

**Interfaces:**
- Produces: `public enum WhoopAutoPair { static func choice(among names: [String]) -> Choice; enum Choice: Equatable { case none, one(Int), several } }`.
- Produces on `LiveHeartRateSensor`: `init(defaults: UserDefaults = .currentAccount)`, `private(set) var rememberedPeripheralID: UUID?`, `func prepareForSession(whoopConnected: Bool)`, `func reconnectIfRemembered()`, `func autoPairWhoop()`, `func forget()`.

- [ ] **Step 1: Write the failing test for the pure choice**

Append inside `struct LiveEffortTests`:

```swift
    @Test func autoPairPicksExactlyOneWhoop() {
        #expect(WhoopAutoPair.choice(among: []) == .none)
        #expect(WhoopAutoPair.choice(among: ["Polar H10"]) == .none)
        #expect(WhoopAutoPair.choice(among: ["Polar H10", "WHOOP 4A0B"]) == .one(1))
        #expect(WhoopAutoPair.choice(among: ["whoop", "WHOOP 4A0B"]) == .several)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -3`
Expected: compile error, `cannot find 'WhoopAutoPair' in scope`.

- [ ] **Step 3: Write the choice**

Create `LifeOSKit/Sources/Integrations/WhoopAutoPair.swift`:

```swift
import Foundation

/// Which discovered sensor to pair without asking. Only a WHOOP, and only
/// when there is exactly one: another person's strap in a gym is not a
/// reading this person owns.
public enum WhoopAutoPair {
    public enum Choice: Equatable, Sendable { case none, one(Int), several }

    public static func choice(among names: [String]) -> Choice {
        let matches = names.indices.filter { names[$0].localizedCaseInsensitiveContains("whoop") }
        switch matches.count {
        case 0: return .none
        case 1: return .one(matches[0])
        default: return .several
        }
    }
}
```

Run: `cd LifeOSKit && swift test --filter LiveEffortTests 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 4: Teach the sensor to remember and reconnect**

In `LIfeOS/Features/Activity/ViewModel/LiveHeartRateSensor.swift`, remove the stub `func prepareForSession(whoopConnected: Bool) {}` from Task 7, then:

After `private var wantsScan = false` add:
```swift
    private let defaults: UserDefaults
    private static let rememberedKey = "lastHeartRateSensorID"
    private var reconnectTimeout: Task<Void, Never>?
    private var autoPairing = false
    private(set) var rememberedPeripheralID: UUID?

    init(defaults: UserDefaults = .currentAccount) {
        self.defaults = defaults
        rememberedPeripheralID = defaults.string(forKey: Self.rememberedKey).flatMap(UUID.init)
        super.init()
    }

    /// Called by the recorder at session start. Reconnects the last sensor,
    /// or looks for a lone WHOOP when the account is connected to WHOOP and
    /// nothing was ever paired here.
    func prepareForSession(whoopConnected: Bool) {
        if rememberedPeripheralID != nil { reconnectIfRemembered() }
        else if whoopConnected { autoPairWhoop() }
    }

    func reconnectIfRemembered() {
        guard let id = rememberedPeripheralID, connectedName == nil else { return }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        guard let central, central.state == .poweredOn else { return }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            status = "Reconnecting to \(known.name ?? "your sensor")…"
            peripheral = known; known.delegate = self
            central.connect(known)
        }
        reconnectTimeout?.cancel()
        reconnectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.connectedName == nil else { return }
            self.status = "Looking for your sensor…"
            self.scan()
        }
    }

    func autoPairWhoop() {
        guard connectedName == nil else { return }
        autoPairing = true
        scan()
        status = "Looking for your WHOOP…"
    }

    /// Drops the remembered sensor. An explicit disconnect means "not this
    /// one next time"; account changes clear the whole suite.
    func forget() {
        rememberedPeripheralID = nil
        defaults.removeObject(forKey: Self.rememberedKey)
    }
```

In `stopScan()` add at the end: `autoPairing = false; reconnectTimeout?.cancel(); reconnectTimeout = nil`.

In `connect(_:)`, replace the first line `disconnect(); stopScan()` with `stopStreaming()`, so choosing or reconnecting a device never forgets the remembered one. Only the explicit `disconnect()` forgets.

In `disconnect()`, add `forget()` as the first line.

In `centralManagerDidUpdateState`, the `.poweredOn` case becomes:
```swift
        case .poweredOn:
            if rememberedPeripheralID != nil, connectedName == nil, peripheral == nil, !wantsScan { reconnectIfRemembered() }
            beginScan()
```

In `centralManager(_:didDiscover:advertisementData:rssi:)`, after the `devices.append(...)` call add:
```swift
        if let id = rememberedPeripheralID, peripheral.identifier == id, self.peripheral == nil {
            connect(devices.last!); return
        }
        if autoPairing {
            switch WhoopAutoPair.choice(among: devices.map(\.name)) {
            case .one(let index): connect(devices[index])
            case .several: stopScan(); status = "More than one WHOOP nearby. Choose one under Manage."
            case .none: break
            }
        }
```

In `centralManager(_:didConnect:)`, after `connectedName = ...` add:
```swift
        reconnectTimeout?.cancel(); autoPairing = false
        rememberedPeripheralID = peripheral.identifier
        defaults.set(peripheral.identifier.uuidString, forKey: Self.rememberedKey)
```

In `centralManager(_:didDisconnectPeripheral:error:)`, keep the existing lines and do not call `forget()`: an accidental drop should reconnect next session.

In `ActivityRecorder`, the recorder must pass its defaults to the sensor: change `let sensor = LiveHeartRateSensor()` to `let sensor: LiveHeartRateSensor` and in `init` set `sensor = LiveHeartRateSensor(defaults: defaults)` before `super.init()`. In `saveFinished()` the line `sensor.disconnect()` must not forget the device: replace it there and in `discard()` with `sensor.stopStreaming()`, and add to the sensor:
```swift
    /// Ends the stream without forgetting the device.
    func stopStreaming() {
        stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; connectedName = nil; bpm = nil; receivedAt = nil
        status = "No sensor connected"
    }
```
and make `disconnect()` call `forget()` then `stopStreaming()`.

- [ ] **Step 5: Extend the checks harness**

In `ActivityRecorderChecks.run()`, before `recorder.deactivate()` near the end add:
```swift
            defaults.set(UUID().uuidString, forKey: "lastHeartRateSensorID")
            let remembering = ActivityRecorder(defaults: defaults, liveActivitiesEnabled: false)
            check(remembering.sensor.rememberedPeripheralID != nil, "Remembered sensor survives relaunch")
            let stranger = ActivityRecorder(defaults: otherDefaults, liveActivitiesEnabled: false)
            check(stranger.sensor.rememberedPeripheralID == nil, "Other account has no remembered sensor")
            remembering.sensor.forget()
            check(defaults.string(forKey: "lastHeartRateSensorID") == nil, "Forget clears the remembered sensor")
            remembering.deactivate(); stranger.deactivate()
```

- [ ] **Step 6: Build, run the checks, then test on hardware**

Build as before. Expected: `** BUILD SUCCEEDED **`. Run the checks page as in Task 7 Step 4. Expected: all `PASS`, including the three new lines.

On the iPhone with WHOOP Heart Rate Broadcast on: run the app from Xcode on the device, open Begin activity, connect the WHOOP once under Manage, finish the activity, then start a new one. Expected: status reads "Reconnecting to WHOOP…" and then "Live · WHOOP" within a few seconds with no tap. Lock the phone for two minutes with the activity running, then check the Live Activity on the lock screen updates its BPM. Record both outcomes in the design QA report in Task 13. If the lock screen stops updating, note it there: the fix is adding `<string>workout-processing</string>` to `UIBackgroundModes` in `Config/App-Info.plist`, which is out of this task's evidence until the hardware says so.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Integrations/WhoopAutoPair.swift LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift LIfeOS/Features/Activity/ViewModel
git commit -m "feat(activity): sensors reconnect on their own

The sensor remembers the last paired peripheral per account and
reconnects it at session start, falling back to a scan after twenty
seconds. A WHOOP-connected account with nothing paired pairs a lone
WHOOP when it sees one, and refuses to guess between several."
```

---

### Task 13: Design QA report, lock screen capture, spec status

**Files:**
- Create: `docs/design/live-session/report.md`
- Modify: `docs/superpowers/specs/2026-09-14-live-session-core-design.md` (status line)

- [ ] **Step 1: Capture the remaining surfaces**

iPad: repeat the Task 11 Step 3 capture loop with `UDID` from `grep "LifeOS-iPad (" ` and file names `session-ipad.png`, `session-ipad-dark.png`.

Lock screen: on the iPhone simulator, launch the real app (no preview arguments), sign in if needed, tap the plus, choose Run, Begin activity, then press Cmd+L in the Simulator window to lock. Run `xcrun simctl io "$UDID" screenshot docs/design/live-session/live-activity-lock-screen.png`. If peers are fighting for the Simulator (see the simulator memory note), take the capture on the physical iPhone instead and AirDrop it into the folder.

Dynamic Island: with the app backgrounded and the activity running, `xcrun simctl io "$UDID" screenshot docs/design/live-session/dynamic-island-compact.png`; long press the island in the simulator (click and hold) and capture `dynamic-island-expanded.png`.

- [ ] **Step 2: Write the report**

Create `docs/design/live-session/report.md` following the section order of `design-qa.md` (Source and scope; Evidence and normalization; Findings; Required fidelity surfaces: typography, spacing, colors, images, copy; Interaction and test evidence). Under Interaction and test evidence list: the `swift test` total, the checks harness output pasted verbatim, and the two hardware outcomes from Task 12 Step 6 (auto-reconnect, lock screen updates while locked). Reference every PNG in the folder by name.

- [ ] **Step 3: Update the spec status**

In `docs/superpowers/specs/2026-09-14-live-session-core-design.md` change the status line to `**Status:** implemented on feat/live-session-core, see docs/design/live-session/report.md`. If the hardware check in Task 12 required the `workout-processing` background mode, add a sentence to section 9 recording that it was added and why.

- [ ] **Step 4: Run everything once more**

Run: `cd LifeOSKit && swift test 2>&1 | tail -3`
Expected: all tests pass, count higher than Task 1's by about 20.

Run the app build. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add docs/design/live-session docs/superpowers/specs/2026-09-14-live-session-core-design.md
git commit -m "docs(activity): design QA for the live session core

Captures of the in-session screen on iPhone and iPad in both schemes,
the lock screen Live Activity and the Dynamic Island, with the checks
output and hardware outcomes."
```

---

## Self-review

**Spec coverage.** 3.1 zones: Task 3. 3.2 effort and credit cap: Task 4. 3.3 capacity, sources, conservative ceiling: Task 5. 3.4 battery and push: Task 5. 3.5 readout in AppSurfaces and the typealias: Task 2, builder in Task 6. 4 recorder changes, draft fields, paused accrual: Task 7. 5.1 throttle: Task 6 and 7. 5.2 and 5.3 lock screen and island, DesignSystem link: Task 9. 6.1 HUD with activity adaptation and accessibility: Task 10. 6.2 in-session hero, tiles, birth-date hint, connections status: Task 11. 7 auto-connect, remembered id, WHOOP auto-pair, forget on disconnect and account change (the per-account suite is dropped with the account already): Task 12. 8 tests and checks and design QA: Tasks 2 to 7, 12, 13. 9 background mode check: Task 12 Step 6.

**Placeholders.** None: every step has its code or its exact command. The bundle identifier and the design-preview launch argument are looked up by a stated grep rather than assumed.

**Type consistency.** `LiveSessionReadout(elapsed:runningSince:push:)` is the only initialiser and every task uses it. `EffortAccumulator(load:)`, `Capacity(percent:source:measuredOn:)`, `RecoveryDay(date:...)`, `CapacityMath.capacity(days:now:calendar:)`, `EffortMath.batteryRemaining(capacity:effort:ceiling:)`, `EffortMath.pushState(zone:effort:ceiling:)`, `LiveReadoutBuilder.readout(timer:heartRate:zones:effort:capacity:energyKcal:distanceMeters:)`, `LiveActivityThrottle.shouldPublish(previous:next:lastPublishedAt:now:)`, `WorkoutLiveActivityController.sync(_:timer:icon:)`, `LiveHeartRateSensor.prepareForSession(whoopConnected:)`, `SessionHUD(readout:activity:zonesAvailable:isExpanded:)` match across tasks. `PushState.tint` is defined once per target (widget and app) because the two targets do not share a SwiftUI module.
