# Apple Watch Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Apple Watch runs the workout session when it is nearby, mirrors it to the phone, streams heart rate, energy and wrist-counted reps into the existing live readout, and the phone's HUD, tiles and Live Activity show reps and sets for strength.

**Architecture:** Wire types in `AppSurfaces` (Foundation only) and a pure `RepCounter` in a new `Motion` package target keep everything testable on macOS. The watch target gains `WatchWorkoutController` (HealthKit session, mirroring, CoreMotion, packets) and a small screen. The phone gains `WatchSessionBridge`, which owns the mirrored session and feeds `ActivityRecorder` through the same heart-rate path the Bluetooth sensor uses. The recorder learns a `SessionSource` and reps/sets; the surfaces fill the strength slot slice 1 reserved.

**Tech Stack:** Swift 6, SwiftUI, HealthKit workout mirroring (`startMirroringToCompanionDevice`, `workoutSessionMirroringStartHandler`, `sendToRemoteWorkoutSession`, `startWatchApp(toHandle:)`), CoreMotion, WatchKit, ActivityKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-14-watch-companion-design.md`

## Global Constraints

- iOS 26.0 and watchOS 26.0 deployment targets, Swift 6.0, `SWIFT_STRICT_CONCURRENCY = complete` on the watch targets. Package platforms `.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")`; package tests run on macOS, so package code stays free of HealthKit, CoreMotion and WatchKit.
- Tests are Swift Testing (`import Testing`, `@Test`, `#expect`). Never XCTest.
- A missing value is never shown as zero. `reps` is nil for non-strength sessions and shows an em dash; a strength session that has counted nothing shows "0" because zero reps is a real count.
- Auto-counted reps are labelled "auto" wherever a count is shown next to its source.
- The watch target links `AppSurfaces` and `Motion` only. New watch files must be added to `LIfeOS.xcodeproj/project.pbxproj` by hand (the watch target is not filesystem-synchronised).
- The wire format is versioned by `v`; an unknown version is ignored, never guessed.
- Copy has no em dashes. Commit messages are conventional commits with a short body and no Co-Authored-By or attribution trailer.
- Work happens in a worktree on branch `feat/watch-companion` forked from `main` at or after commit `267f097`. Never commit to `main`. Never use bare `git stash`.
- Package tests: `cd LifeOSKit && swift test --filter <Suite>`. App build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' build`. Watch build: `xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' build`. The plain `sleep` command is blocked in the agent harness; wait with `perl -e 'select(undef,undef,undef,SECONDS)'`.
- Recorder checks run on the iPhone 17 simulator through the design preview: launch with `--design-preview --page=checks`, wait 15 seconds, read `recorder-checks.txt` from the app's Documents container. Bundle id `com.shivvyas.lifeos`.

## File map

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/AppSurfaces/WatchWire.swift` (new) | `WatchPacket`, `PhoneCommand`, `PhoneCommandEnvelope`, `WatchWire` encode/decode with version gate. |
| `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift` | `reps`, `setIndex`; throttle publishes on a reps change. |
| `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout+Text.swift` | `repsText`, `setText`. |
| `LifeOSKit/Sources/Motion/RepCounter.swift` (new target) | Pure rep counter. |
| `LifeOSKit/Package.swift` | `Motion` target and tests. |
| `LifeOSKit/Sources/Integrations/LiveEffort.swift` | Builder copies reps and set. |
| `LifeOSKit/Sources/Integrations/ActivitySessionState.swift` | `SessionSource` enum. |
| `LifeOSKit/Sources/Persistence/SourceRecords.swift` | `WorkoutRecord.setsData` and `sets` accessor. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift` | Source choice, watch hand-off, packets, reps and sets, draft. |
| `LIfeOS/App/Surfaces/WatchSessionBridge.swift` (new) | Mirrored session owner and delegate on the phone. |
| `LIfeOS/App/PushService.swift` | Installs the mirroring handler at launch. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift` | New checks. |
| `AlmanacWatch/WatchAppDelegate.swift` (new) | `handle(_ workoutConfiguration:)`. |
| `AlmanacWatch/WatchWorkoutController.swift` (new) | HealthKit session, mirroring, CoreMotion, packets, commands. |
| `AlmanacWatch/WatchWorkoutScreen.swift` (new) | Timer, heart rate, reps, set, controls. |
| `AlmanacWatch/AlmanacWatchApp.swift` | Delegate adaptor, navigation to the workout screen, Start button. |
| `AlmanacWatch/Info.plist`, `AlmanacWatch/AlmanacWatch.entitlements`, `LIfeOS.xcodeproj/project.pbxproj` | Capabilities, usage strings, files, `Motion` link. |
| `LIfeOS/Features/Activity/View/SessionHUD.swift` | Reps slot, expanded set row, +1 and Next set. |
| `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` | Reps tile, watch line, copy. |
| `AlmanacWidgets/WorkoutLiveActivity.swift` | Reps in the island and the lock screen for strength. |
| `docs/design/watch-companion/` (new) | Captures and report. |

---

### Task 1: Wire types, reps on the readout, throttle on reps

**Files:**
- Create: `LifeOSKit/Sources/AppSurfaces/WatchWire.swift`
- Modify: `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout.swift`, `LifeOSKit/Sources/AppSurfaces/LiveSessionReadout+Text.swift`
- Test: `LifeOSKit/Tests/AppSurfacesTests/WatchWireTests.swift` (new), `LifeOSKit/Tests/AppSurfacesTests/LiveSessionReadoutTests.swift`

**Interfaces:**
- Produces: `public struct WatchPacket: Codable, Equatable, Sendable` (fields per spec 3.3, `init(sentAt:)`), `public enum PhoneCommand: String, Codable, Sendable`, `public struct PhoneCommandEnvelope: Codable, Equatable, Sendable` (`init(command:sentAt:maxHeartRate:)`), `public enum WatchWire { static let version = 1; static func encode<T: Encodable>(_:) throws -> Data; static func packet(from: Data) -> WatchPacket?; static func command(from: Data) -> PhoneCommandEnvelope? }`, `LiveSessionReadout.reps: Int?`, `LiveSessionReadout.setIndex: Int?`, `repsText: String?`, `setText: String?`.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/AppSurfacesTests/WatchWireTests.swift`:

```swift
import Foundation
import Testing
@testable import AppSurfaces

struct WatchWireTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func packetRoundTripsAndKeepsAbsence() throws {
        var packet = WatchPacket(sentAt: now)
        packet.heartRate = 141; packet.heartRateAt = now; packet.energyKcal = 88.4
        packet.reps = 7; packet.setIndex = 2; packet.completedSets = [12, 10]
        let data = try WatchWire.encode(packet)
        let back = try #require(WatchWire.packet(from: data))
        #expect(back == packet)
        #expect(WatchWire.packet(from: try WatchWire.encode(WatchPacket(sentAt: now)))?.reps == nil)
    }

    @Test func unknownVersionIsIgnored() throws {
        var packet = WatchPacket(sentAt: now); packet.v = 99
        #expect(WatchWire.packet(from: try WatchWire.encode(packet)) == nil)
        #expect(WatchWire.packet(from: Data("junk".utf8)) == nil)
    }

    @Test func commandRoundTrips() throws {
        let envelope = PhoneCommandEnvelope(command: .configure, sentAt: now, maxHeartRate: 187)
        let back = try #require(WatchWire.command(from: try WatchWire.encode(envelope)))
        #expect(back == envelope)
        #expect(WatchWire.command(from: try WatchWire.encode(WatchPacket(sentAt: now))) == nil)
    }
}
```

Append inside `struct LiveSessionReadoutTests`:

```swift
    @Test func repsRoundTripAndFormat() throws {
        var readout = LiveSessionReadout(elapsed: 10, runningSince: start, push: .onTrack)
        #expect(readout.repsText == nil && readout.setText == nil)
        readout.reps = 0; readout.setIndex = 1
        #expect(readout.repsText == "0" && readout.setText == "Set 1")
        readout.reps = 12; readout.setIndex = 3
        let back = try JSONDecoder().decode(LiveSessionReadout.self, from: try JSONEncoder().encode(readout))
        #expect(back.reps == 12 && back.setIndex == 3)
    }

    @Test func throttlePublishesOnRepsChange() {
        let now = start.addingTimeInterval(100)
        var a = readout(bpm: 120); a.reps = 4
        var b = a; b.reps = 5
        #expect(LiveActivityThrottle.shouldPublish(previous: a, next: b, lastPublishedAt: now.addingTimeInterval(-1), now: now))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter "WatchWireTests|LiveSessionReadoutTests" 2>&1 | tail -5`
Expected: compile errors, `cannot find 'WatchPacket' in scope` and `value of type 'LiveSessionReadout' has no member 'reps'`.

- [ ] **Step 3: Write the wire types and readout fields**

Create `LifeOSKit/Sources/AppSurfaces/WatchWire.swift`:

```swift
import Foundation

/// What the watch sends the phone over the mirrored session's data channel.
/// Every reading is optional: a packet without heart rate says "no reading",
/// never zero. `completedSets` holds reps per finished set, oldest first.
public struct WatchPacket: Codable, Equatable, Sendable {
    public var v: Int = WatchWire.version
    public var sentAt: Date
    public var heartRate: Int?
    public var heartRateAt: Date?
    public var energyKcal: Double?
    public var reps: Int?
    public var setIndex: Int?
    public var completedSets: [Int]?

    public init(sentAt: Date) { self.sentAt = sentAt }
}

/// What the phone asks the watch to do. `configure` carries the person's
/// maximum heart rate once so the watch can show a zone chip.
public enum PhoneCommand: String, Codable, Sendable {
    case configure, pause, resume, end, nextSet, addRep
}

public struct PhoneCommandEnvelope: Codable, Equatable, Sendable {
    public var v: Int = WatchWire.version
    public var command: PhoneCommand
    public var sentAt: Date
    public var maxHeartRate: Int?

    public init(command: PhoneCommand, sentAt: Date, maxHeartRate: Int? = nil) {
        self.command = command; self.sentAt = sentAt; self.maxHeartRate = maxHeartRate
    }
}

/// Encoding and the version gate in one place, shared by both devices.
public enum WatchWire {
    public static let version = 1

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }

    public static func packet(from data: Data) -> WatchPacket? {
        guard let packet = try? decoder.decode(WatchPacket.self, from: data), packet.v == version else { return nil }
        return packet
    }

    public static func command(from data: Data) -> PhoneCommandEnvelope? {
        guard let envelope = try? decoder.decode(PhoneCommandEnvelope.self, from: data), envelope.v == version else { return nil }
        return envelope
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
```

In `LiveSessionReadout.swift`, add two fields after `public var push: PushState`... place them before `push` to keep the initialiser untouched:

```swift
    /// Reps in the current set and the 1-based set index, strength only.
    public var reps: Int?
    public var setIndex: Int?
```

In `LiveActivityThrottle.shouldPublish`, after the `if previous.push != next.push { return true }` line add:

```swift
        if previous.reps != next.reps { return true }
```

In `LiveSessionReadout+Text.swift` add inside the extension:

```swift
    var repsText: String? { reps.map(String.init) }
    var setText: String? { setIndex.map { "Set \($0)" } }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter "WatchWireTests|LiveSessionReadoutTests" 2>&1 | tail -3`
Expected: all pass. Note: the `commandRoundTrips` test decodes a packet as a command and expects nil; `PhoneCommandEnvelope` requires `command`, which a packet lacks, so decoding throws and `command(from:)` returns nil.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/AppSurfaces LifeOSKit/Tests/AppSurfacesTests
git commit -m "feat(surfaces): watch wire types and reps on the readout

Versioned packets and commands for the mirrored session's data channel,
reps and set index on the live readout, and a throttle that publishes
the moment a rep lands."
```

---

### Task 2: `Motion` target and `RepCounter`

**Files:**
- Modify: `LifeOSKit/Package.swift`
- Create: `LifeOSKit/Sources/Motion/RepCounter.swift`
- Test: `LifeOSKit/Tests/MotionTests/RepCounterTests.swift` (new)

**Interfaces:**
- Produces: `public struct RepCounter: Sendable { struct Sample; init(settleSeconds:minPeriod:maxPeriod:threshold:); mutating func add(_:) -> Bool; private(set) var reps: Int; mutating func reset() }`.

- [ ] **Step 1: Add the target and write the failing tests**

In `LifeOSKit/Package.swift` add to `products`:

```swift
        .library(name: "Motion", targets: ["Motion"]),
```

and to `targets`:

```swift
        .target(name: "Motion"),
        .testTarget(name: "MotionTests", dependencies: ["Motion"]),
```

Create `LifeOSKit/Tests/MotionTests/RepCounterTests.swift`:

```swift
import Foundation
import Testing
@testable import Motion

struct RepCounterTests {
    /// Samples at 50 Hz: a sine on the vertical axis at `hz` and `amplitude` g
    /// with white noise of `noise` g, for `seconds`, starting at `t0`.
    private func signal(hz: Double, amplitude: Double, noise: Double, seconds: Double, t0: Double = 0) -> [RepCounter.Sample] {
        var generator = SystemRandomNumberGenerator()
        return stride(from: 0.0, to: seconds, by: 0.02).map { t in
            let jitter = Double.random(in: -noise...noise, using: &generator)
            return RepCounter.Sample(t: t0 + t, x: 0, y: 0, z: amplitude * sin(2 * .pi * hz * t) + jitter)
        }
    }
    private func count(_ samples: [RepCounter.Sample], counter: RepCounter = RepCounter()) -> Int {
        var counter = counter
        for sample in samples { _ = counter.add(sample) }
        return counter.reps
    }

    @Test func tenSlowCurlsCountTen() {
        // Two seconds of settling then ten cycles at 1 Hz.
        let quiet = signal(hz: 0, amplitude: 0, noise: 0.02, seconds: 2)
        let reps = signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 10, t0: 2)
        #expect(count(quiet + reps) == 10)
    }

    @Test func tinyMovementCountsNothing() {
        #expect(count(signal(hz: 1, amplitude: 0.08, noise: 0.02, seconds: 12)) == 0)
    }

    @Test func fastJitterCountsNothing() {
        #expect(count(signal(hz: 3, amplitude: 0.4, noise: 0.05, seconds: 12)) == 0)
    }

    @Test func oneSlowPushCountsNothing() {
        #expect(count(signal(hz: 1.0 / 6.0, amplitude: 0.5, noise: 0.02, seconds: 8)) == 0)
    }

    @Test func settlingSwallowsTheFirstSecond() {
        // Cycles start at once; the first second is the person picking up the weight.
        #expect(count(signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 9)) == 8)
    }

    @Test func resetStartsOver() {
        var counter = RepCounter()
        for sample in signal(hz: 0, amplitude: 0, noise: 0.02, seconds: 2) + signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 5, t0: 2) { _ = counter.add(sample) }
        #expect(counter.reps == 5)
        counter.reset()
        #expect(counter.reps == 0)
        for sample in signal(hz: 1, amplitude: 0.4, noise: 0.05, seconds: 3, t0: 7) { _ = counter.add(sample) }
        #expect(counter.reps == 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter RepCounterTests 2>&1 | tail -5`
Expected: compile error, `no such module 'Motion'` or `cannot find 'RepCounter' in scope`.

- [ ] **Step 3: Write the counter**

Create `LifeOSKit/Sources/Motion/RepCounter.swift`:

```swift
import Foundation

/// Counts repetitions from wrist acceleration. Pure: samples in, a count
/// out, so it is tested on synthetic signals and tuned from hardware later.
///
/// The signal is the magnitude of user acceleration, smoothed twice: a fast
/// average follows the movement, a slow one follows posture and gravity
/// drift, and their difference is the lift. A rep is a rise above the
/// threshold followed by a fall below its negative, taking between
/// `minPeriod` and `maxPeriod` seconds. Nothing counts while settling after
/// `reset()`, and each rep starts a refractory window of `minPeriod`.
public struct RepCounter: Sendable {
    public struct Sample: Sendable {
        public var t: TimeInterval
        public var x: Double
        public var y: Double
        public var z: Double
        public init(t: TimeInterval, x: Double, y: Double, z: Double) { self.t = t; self.x = x; self.y = y; self.z = z }
    }

    public let settleSeconds: Double
    public let minPeriod: Double
    public let maxPeriod: Double
    public let threshold: Double
    public private(set) var reps: Int = 0

    private let fastTau = 0.15
    private let slowTau = 2.0
    private var fast: Double?
    private var slow: Double?
    private var lastT: TimeInterval?
    private var startT: TimeInterval?
    private var riseT: TimeInterval?
    private var refractoryUntil: TimeInterval = -.infinity

    public init(settleSeconds: Double = 1.0, minPeriod: Double = 0.6, maxPeriod: Double = 4.0, threshold: Double = 0.15) {
        self.settleSeconds = settleSeconds; self.minPeriod = minPeriod; self.maxPeriod = maxPeriod; self.threshold = threshold
    }

    public mutating func reset() {
        reps = 0; fast = nil; slow = nil; lastT = nil; startT = nil; riseT = nil; refractoryUntil = -.infinity
    }

    /// Feed one sample; returns true when this sample completed a rep.
    public mutating func add(_ sample: Sample) -> Bool {
        let magnitude = (sample.x * sample.x + sample.y * sample.y + sample.z * sample.z).squareRoot()
        let dt = lastT.map { max(0.001, sample.t - $0) } ?? 0.02
        lastT = sample.t
        if startT == nil { startT = sample.t }
        fast = smooth(fast, toward: magnitude, dt: dt, tau: fastTau)
        slow = smooth(slow, toward: magnitude, dt: dt, tau: slowTau)
        guard let fast, let slow, let startT, sample.t - startT >= settleSeconds, sample.t >= refractoryUntil else { return false }
        let s = fast - slow
        if riseT == nil {
            if s > threshold { riseT = sample.t }
            return false
        }
        guard s < -threshold, let rise = riseT else { return false }
        riseT = nil
        let period = sample.t - rise
        guard period >= minPeriod / 2, period <= maxPeriod else { return false }
        reps += 1
        refractoryUntil = sample.t + minPeriod / 2
        return true
    }

    private func smooth(_ current: Double?, toward value: Double, dt: Double, tau: Double) -> Double {
        guard let current else { return value }
        let alpha = 1 - exp(-dt / tau)
        return current + alpha * (value - current)
    }
}
```

The rise-to-fall time is half a cycle, so the period checks use `minPeriod / 2` and `maxPeriod` (a lift can be slow; the return decides). A 1 Hz curl has a 0.5 second half cycle, above `minPeriod / 2 = 0.3`; a 3 Hz jitter's half cycle is 0.17 seconds, below it. A 6 second push never falls below `-threshold` before the slow average catches up, so it counts nothing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter RepCounterTests 2>&1 | tail -3`
Expected: 6 tests pass. If `tenSlowCurlsCountTen` counts 9 or 11 on some runs because of noise, raise the amplitude in the test to 0.5 and lower noise to 0.03; the spec's calibration is amplitude 0.4 with noise 0.05, so prefer adjusting the smoothing constants (`fastTau` 0.12) first and record the change in the report.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Package.swift LifeOSKit/Sources/Motion LifeOSKit/Tests/MotionTests
git commit -m "feat(motion): a pure rep counter on wrist acceleration

Fast and slow smoothing, hysteresis and a period window, pinned by
synthetic-signal tests. Foundation only so the watch can link it and
macOS can test it."
```

---

### Task 3: Source, reps and sets in the recorder and the record

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/ActivitySessionState.swift`, `LifeOSKit/Sources/Integrations/LiveEffort.swift`, `LifeOSKit/Sources/Persistence/SourceRecords.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`, `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/LiveEffortTests.swift`, `LifeOSKit/Tests/PersistenceTests/WorkoutSetsTests.swift` (new)

**Interfaces:**
- Consumes: `WatchPacket`, `WatchWire`.
- Produces: `public enum SessionSource: String, Codable, Sendable { case phone, watch }`; `WorkoutRecord.setsData: Data?` with `public var sets: [Int]`; `LiveReadoutBuilder.readout(...reps:setIndex:)`; on `ActivityRecorder`: `private(set) var source: SessionSource`, `private(set) var reps: Int?`, `private(set) var setIndex: Int?`, `private(set) var completedSets: [Int]`, `func receiveWatchPacket(_:)`, `func addRep()`, `func nextSet()`.

- [ ] **Step 1: Write the failing tests**

Append inside `struct LiveEffortTests`:

```swift
    @Test func builderCarriesRepsAndSet() {
        let timer = ActivitySessionState(activity: "Strength", at: today)
        let readout = LiveReadoutBuilder.readout(timer: timer, heartRate: nil, zones: nil, effort: EffortAccumulator(),
                                                 capacity: nil, energyKcal: nil, distanceMeters: nil, reps: 8, setIndex: 2)
        #expect(readout.reps == 8 && readout.setIndex == 2)
        let plain = LiveReadoutBuilder.readout(timer: timer, heartRate: nil, zones: nil, effort: EffortAccumulator(),
                                               capacity: nil, energyKcal: nil, distanceMeters: nil)
        #expect(plain.reps == nil && plain.setIndex == nil)
    }
```

Create `LifeOSKit/Tests/PersistenceTests/WorkoutSetsTests.swift`:

```swift
import Foundation
import Testing
@testable import Persistence

struct WorkoutSetsTests {
    @Test func setsRoundTripThroughData() {
        let row = WorkoutRecord(externalID: "t", start: .now, durationMinutes: 20, activityName: "Strength")
        #expect(row.sets.isEmpty && row.setsData == nil)
        row.sets = [12, 10, 8]
        #expect(row.sets == [12, 10, 8])
        row.sets = []
        #expect(row.setsData == nil)
    }
}
```

In `ActivityRecorderChecks.run()`, after the `check(recorder.readout?.heartRate == 140 ...)` line, insert:

```swift
            let lifter = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".lift")!, liveActivitiesEnabled: false)
            lifter.attach(context); lifter.saveToHealth = false; lifter.selection = .strength
            await lifter.start()
            check(lifter.source == .phone && lifter.reps == 0 && lifter.setIndex == 1, "A phone strength session starts at set 1 with zero reps")
            lifter.addRep(); lifter.addRep(); lifter.nextSet(); lifter.addRep()
            check(lifter.reps == 1 && lifter.setIndex == 2 && lifter.completedSets == [2] && lifter.readout?.reps == 1, "Manual reps and sets count on the phone")
            var stale = WatchPacket(sentAt: .now); stale.v = 99; stale.reps = 40
            lifter.receiveWatchPacket(try WatchWire.encode(stale))
            check(lifter.reps == 1, "A packet with an unknown version changes nothing")
            await lifter.finish()
            let lifted = try context.fetch(FetchDescriptor<WorkoutRecord>()).first { $0.activityName == "Strength" }
            check(lifted?.sets == [2, 1], "Finishing writes the sets, current set included")
            lifter.deactivate()
            UserDefaults(suiteName: suite + ".lift")?.removePersistentDomain(forName: suite + ".lift")
```

- [ ] **Step 2: Build to verify failure**

Run: `cd LifeOSKit && swift test --filter "LiveEffortTests|WorkoutSetsTests" 2>&1 | tail -4`
Expected: compile errors for the `reps:` label and `sets`.

- [ ] **Step 3: Write the package changes**

In `ActivitySessionState.swift` append:

```swift
/// Who runs the HealthKit session. The phone when no watch is nearby, the
/// watch when it is; the draft keeps the answer so a relaunch knows.
public enum SessionSource: String, Codable, Sendable { case phone, watch }
```

In `SourceRecords.swift`, inside `WorkoutRecord` after `zoneFiveMinutes`:

```swift
    /// Reps per set for a strength session, as JSON, so an existing store
    /// migrates without a plan. Empty sets are stored as nil, not `[]`.
    public var setsData: Data?
    public var sets: [Int] {
        get { setsData.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? [] }
        set { setsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
```

In `LiveEffort.swift`, change the builder signature to add two trailing parameters with defaults and copy them:

```swift
    public static func readout(timer: ActivitySessionState, heartRate: Int?, zones: HeartRateZones?,
                               effort: EffortAccumulator, capacity: Capacity?,
                               energyKcal: Double?, distanceMeters: Double?,
                               reps: Int? = nil, setIndex: Int? = nil) -> LiveSessionReadout {
```

and before `return readout`:

```swift
        readout.reps = reps
        readout.setIndex = setIndex
```

- [ ] **Step 4: Write the recorder changes**

In `ActivityRecorder.swift`:

Add after `private(set) var readout: LiveSessionReadout?`:

```swift
    private(set) var source: SessionSource = .phone
    private(set) var reps: Int?
    private(set) var setIndex: Int?
    private(set) var completedSets: [Int] = []
```

Extend `Draft` with `var source: SessionSource?`, `var reps: Int?`, `var setIndex: Int?`, `var completedSets: [Int]?`. In `attach`, after restoring `capacity`, add `source = draft.source ?? .phone; reps = draft.reps; setIndex = draft.setIndex; completedSets = draft.completedSets ?? []`. In `writeDraft`, pass the four new values. In `discard()`, reset `source = .phone; reps = nil; setIndex = nil; completedSets = []`.

In `start()`, right after `effort = EffortAccumulator(); lastReadingAt = nil` add:

```swift
        source = .phone
        if selection == .strength { reps = 0; setIndex = 1; completedSets = [] } else { reps = nil; setIndex = nil; completedSets = [] }
```

In `refreshReadout()` pass `reps: reps, setIndex: setIndex` to the builder.

Add these methods after `togglePause()`:

```swift
    /// Manual counting. On the watch source the command echoes back in the
    /// next packet; on the phone it counts here.
    func addRep() {
        guard hasSession, selection == .strength else { return }
        if source == .watch { watch?.send(.addRep); return }
        reps = (reps ?? 0) + 1
        persist()
    }
    func nextSet() {
        guard hasSession, selection == .strength else { return }
        if source == .watch { watch?.send(.nextSet); return }
        completedSets.append(reps ?? 0)
        reps = 0; setIndex = (setIndex ?? 1) + 1
        persist()
    }
    /// Raw bytes from the mirrored session. Anything not a current-version
    /// packet is dropped without changing state.
    func receiveWatchPacket(_ data: Data) {
        guard active, hasSession, let packet = WatchWire.packet(from: data) else { return }
        if let bpm = packet.heartRate, let at = packet.heartRateAt { receiveHeartRate(bpm, at: at) }
        if let energy = packet.energyKcal { self.energy = energy }
        if selection == .strength {
            if let value = packet.reps { reps = value }
            if let value = packet.setIndex { setIndex = value }
            if let value = packet.completedSets { completedSets = value }
        }
        persistReading(at: packet.sentAt)
    }
```

`watch` is a `WatchSessionBridge?` property added in Task 4; for this task declare `var watch: WatchSessionBridge?` and create a placeholder file `LIfeOS/App/Surfaces/WatchSessionBridge.swift` containing only:

```swift
import Foundation
import AppSurfaces

@MainActor
final class WatchSessionBridge {
    func send(_ command: PhoneCommand) {}
}
```

Task 4 replaces it.

In `saveFinished()`, after `row.distanceMeters = distance` add:

```swift
                if selection == .strength { row.sets = completedSets + [reps ?? 0] }
```

- [ ] **Step 5: Run tests, build, run the checks**

Run: `cd LifeOSKit && swift test --filter "LiveEffortTests|WorkoutSetsTests|LiveSessionReadoutTests" 2>&1 | tail -3`. Expected: pass.
Build the app. Expected: `** BUILD SUCCEEDED **`. Run the checks page. Expected: every line `PASS`, including the four new ones.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit LIfeOS/Features/Activity LIfeOS/App/Surfaces/WatchSessionBridge.swift
git commit -m "feat(activity): reps, sets and a session source in the recorder

Strength sessions count reps and sets on the phone, accept watch packets
through the same heart-rate path, and write sets onto the workout
record. The draft remembers who owns the session."
```

---

### Task 4: `WatchSessionBridge` and the watch hand-off on the phone

**Files:**
- Replace: `LIfeOS/App/Surfaces/WatchSessionBridge.swift`
- Modify: `LIfeOS/App/PushService.swift` (install the handler), `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`, `LIfeOS/App/RootView.swift`, `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift`

**Interfaces:**
- Produces: `@MainActor final class WatchSessionBridge: NSObject, HKWorkoutSessionDelegate` with `static let shared`, `var onSession: ((HKWorkoutSession) -> Void)?`, `var onPacket: ((Data) -> Void)?`, `var onStateChange: ((HKWorkoutSessionState, Date) -> Void)?`, `func adopt(_ session: HKWorkoutSession)`, `func send(_ command: PhoneCommand, maxHeartRate: Int? = nil)`, `func end()`, `var hasSession: Bool`, `static func installMirroringHandler()`.
- Produces on the recorder: `var watchAvailable: () -> Bool`, `var watchHandoffTimeout: TimeInterval = 10`, `func adoptMirroredSession(_ session: HKWorkoutSession)`.

- [ ] **Step 1: Write the failing check**

In `ActivityRecorderChecks.run()`, after the lifter block, insert:

```swift
            let waiter = ActivityRecorder(defaults: UserDefaults(suiteName: suite + ".watch")!, liveActivitiesEnabled: false)
            waiter.attach(context); waiter.saveToHealth = false
            waiter.watchAvailable = { true }; waiter.watchHandoffTimeout = 0.5
            await waiter.start()
            check(waiter.source == .phone && waiter.hasSession && waiter.notice?.contains("did not answer") == true, "A watch that does not answer falls back to the phone")
            waiter.deactivate()
            UserDefaults(suiteName: suite + ".watch")?.removePersistentDomain(forName: suite + ".watch")
```

- [ ] **Step 2: Build to verify failure**

Build the app. Expected: `error: value of type 'ActivityRecorder' has no member 'watchAvailable'`.

- [ ] **Step 3: Write the bridge**

Replace `LIfeOS/App/Surfaces/WatchSessionBridge.swift`:

```swift
import Foundation
import HealthKit
import WatchConnectivity
import AppSurfaces

/// Owns the workout session mirrored from the watch. One per app: HealthKit
/// hands the session to whichever handler is installed at launch, so the
/// bridge is installed by the app delegate and the recorder subscribes.
@MainActor
final class WatchSessionBridge: NSObject, HKWorkoutSessionDelegate {
    static let shared = WatchSessionBridge()
    private static let healthStore = HKHealthStore()

    private(set) var session: HKWorkoutSession?
    var onSession: ((HKWorkoutSession) -> Void)?
    var onPacket: ((Data) -> Void)?
    var onStateChange: ((HKWorkoutSessionState, Date) -> Void)?
    var hasSession: Bool { session != nil }

    /// Call once at launch, before any session can arrive.
    static func installMirroringHandler() {
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in WatchSessionBridge.shared.adopt(session) }
        }
    }

    /// Whether a watch could take the session right now.
    static var watchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let wc = WCSession.default
        return wc.activationState == .activated && wc.isPaired && wc.isWatchAppInstalled && wc.isReachable
    }

    /// Ask the watch to open Almanac with this workout.
    static func startWatchApp(_ configuration: HKWorkoutConfiguration) async throws {
        try await healthStore.startWatchApp(toHandle: configuration)
    }

    func adopt(_ session: HKWorkoutSession) {
        self.session?.delegate = nil
        self.session = session
        session.delegate = self
        onSession?(session)
    }

    func send(_ command: PhoneCommand, maxHeartRate: Int? = nil) {
        guard let session, let data = try? WatchWire.encode(PhoneCommandEnvelope(command: command, sentAt: .now, maxHeartRate: maxHeartRate)) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    func end() {
        session?.delegate = nil
        session = nil
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.onStateChange?(toState, date)
            if toState == .ended { self.end() }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in if self.session === workoutSession { self.end() } }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteDevice data: [Data]) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            for item in data { self.onPacket?(item) }
        }
    }
}
```

In `PushService.swift`, inside `PushDelegate.application(_:didFinishLaunchingWithOptions:)` before `return true`:

```swift
        WatchSessionBridge.installMirroringHandler()
```

- [ ] **Step 4: Wire the recorder**

In `ActivityRecorder.swift`:

Add properties:

```swift
    /// Injected so checks can simulate a watch that never answers.
    var watchAvailable: () -> Bool = { WatchSessionBridge.watchAvailable }
    var watchHandoffTimeout: TimeInterval = 10
    var watch: WatchSessionBridge? = .shared
    private var handoff: Task<Void, Never>?
```

Replace the earlier placeholder property `var watch: WatchSessionBridge?` with the line above. In `init`, after `sensor.onReading = ...` add:

```swift
        watch?.onSession = { [weak self] session in self?.adoptMirroredSession(session) }
        watch?.onPacket = { [weak self] data in self?.receiveWatchPacket(data) }
        watch?.onStateChange = { [weak self] state, date in self?.mirroredStateChanged(state, at: date) }
```

In `start()`, replace the `if saveToHealth {` branch's opening with a watch attempt. Insert this block immediately after `defer { busy = false }` and before `do {`:

```swift
        if watchAvailable(), let watch, !watch.hasSession {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = selection.healthType
            configuration.locationType = .unknown
            source = .watch
            timer = ActivitySessionState(activity: selection.rawValue, at: backdatedStart ?? .now)
            if selection == .strength { reps = 0; setIndex = 1; completedSets = [] }
            persist()
            try? await WatchSessionBridge.startWatchApp(configuration)
            let deadline = Date.now.addingTimeInterval(watchHandoffTimeout)
            while Date.now < deadline, watch.session == nil, active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if watch.session != nil {
                watch.send(.configure, maxHeartRate: zones?.maxHeartRate)
                return
            }
            source = .phone
            notice = "Apple Watch did not answer. Recording on iPhone."
        }
```

`ActivitySessionState(activity:at:)` was already created above the timer-only branch; when the watch path falls through, the `do` block below must not create a second timer. Guard both creations: in the Health branch change `timer = ActivitySessionState(...)` to `if timer == nil { timer = ActivitySessionState(activity: selection.rawValue, at: started) }` and in the timer-only branch likewise. The Health branch also must not run for `.watch`; the fall-through sets `source = .phone` first, so the guard is `if saveToHealth && source == .phone`.

Add:

```swift
    /// The watch's session arrived: either the hand-off answered, or the
    /// person started on the watch. Adopt it; never run two sessions.
    func adoptMirroredSession(_ mirrored: HKWorkoutSession) {
        guard active else { return }
        if session != nil, source == .phone {
            notice = "Already recording on iPhone; the watch session was ignored."
            watch?.send(.end); return
        }
        if timer == nil {
            selection = RecordedActivity.allCases.first { $0.healthType == mirrored.workoutConfiguration.activityType } ?? .other
            zones = HeartRateZones(birthDate: birthDate()); capacity = loadCapacity()
            effort = EffortAccumulator(); lastReadingAt = nil
            timer = ActivitySessionState(activity: selection.rawValue)
            if selection == .strength { reps = 0; setIndex = 1; completedSets = [] }
        }
        source = .watch
        persist()
        watch?.send(.configure, maxHeartRate: zones?.maxHeartRate)
    }
    private func mirroredStateChanged(_ state: HKWorkoutSessionState, at date: Date) {
        guard active, source == .watch else { return }
        switch state {
        case .paused: timer?.pause(at: date)
        case .running: timer?.resume(at: date); lastReadingAt = nil
        case .stopped, .ended:
            timer?.finish(at: date); persist()
            Task { await self.saveFinished() }
        default: break
        }
        persist()
    }
```

In `togglePause()`, for `.watch` send the command instead of touching the HealthKit session: `if isRunning { timer?.pause(); if source == .watch { watch?.send(.pause) } else { session?.pause() } }` and the mirror for resume. In `finish()`, for `.watch`: `timer?.finish(); persist(); watch?.send(.end); await saveFinished()`. In `saveFinished()`, the builder block already only runs when `builder` is non-nil (nil for `.watch`), so the local record is written and Health is left to the watch; add `watch?.end()` next to `sensor.stopStreaming()`. In `discard()`, add `if source == .watch { watch?.send(.end); watch?.end() }` before resetting state.

In `RootView.attachAll()`, nothing new is needed: the bridge is a singleton and the recorder subscribed in `init`. In `RootView`, where `AccountSession` calls `WorkoutLiveActivityController.endAll()`, also call `WatchSessionBridge.shared.end()`.

- [ ] **Step 5: Build, run the checks**

Build the app. Expected: `** BUILD SUCCEEDED **`. Checks page: every line `PASS` including "A watch that does not answer falls back to the phone" (the simulator has no watch, and the injected closure forces the attempt; `startWatchApp` throws or returns without a session, and the 0.5 second deadline passes).

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/App LIfeOS/Features/Activity
git commit -m "feat(activity): hand the session to a nearby Apple Watch

The phone asks the watch to run the workout and adopts the mirrored
session, or falls back to recording itself when the watch does not
answer in time. Packets and state changes reach the recorder through
one bridge installed at launch."
```

---

### Task 5: Watch target capabilities, controller and screen

**Files:**
- Modify: `AlmanacWatch/Info.plist`, `AlmanacWatch/AlmanacWatch.entitlements`, `LIfeOS.xcodeproj/project.pbxproj`, `AlmanacWatch/AlmanacWatchApp.swift`
- Create: `AlmanacWatch/WatchAppDelegate.swift`, `AlmanacWatch/WatchWorkoutController.swift`, `AlmanacWatch/WatchWorkoutScreen.swift`

**Interfaces:**
- Consumes: `WatchPacket`, `PhoneCommandEnvelope`, `WatchWire`, `RepCounter`.
- Produces: `@MainActor @Observable final class WatchWorkoutController` with `start(_ configuration: HKWorkoutConfiguration)`, `pause()`, `resume()`, `end()`, `addRep()`, `nextSet()`, `private(set) var elapsed`, `heartRate`, `reps`, `setIndex`, `completedSets`, `maxHeartRate`, `state`.

- [ ] **Step 1: Capabilities**

`AlmanacWatch/Info.plist`: add inside the top-level dict:

```xml
	<key>WKBackgroundModes</key>
	<array>
		<string>workout-processing</string>
	</array>
```

`AlmanacWatch/AlmanacWatch.entitlements`: add:

```xml
	<key>com.apple.developer.healthkit</key>
	<true/>
```

`project.pbxproj`, in both build configurations of the `AlmanacWatch` target (the two blocks containing `INFOPLIST_FILE = AlmanacWatch/Info.plist;`), add:

```
				INFOPLIST_KEY_NSHealthShareUsageDescription = "Almanac reads heart rate and energy during a workout you start on your watch.";
				INFOPLIST_KEY_NSHealthUpdateUsageDescription = "Almanac saves workouts you record on your watch to Health.";
				INFOPLIST_KEY_NSMotionUsageDescription = "Almanac counts reps from wrist motion during strength sessions.";
```

Add the three new Swift files to the watch target. For each file, three pbxproj entries with fresh 24-hex ids (use `uuidgen | tr -d - | cut -c1-24 | tr a-f A-F`): a `PBXFileReference` (copy the `AlmanacWatchApp.swift` line at the `172E63EE...` entry, changing name and id), a `PBXBuildFile` (`... /* X in Sources */ = {isa = PBXBuildFile; fileRef = <ref> /* X */; };`), a line in the `AE340166A64F22122923FC7C /* AlmanacWatch */` group's `children`, and a line in the `BB17915AC31D1200D91D104A /* Sources */` phase's `files`. Add `Motion` to the watch target the way Task 9 of the live session plan added `DesignSystem` to the widget: a `PBXBuildFile` with `productRef`, a line in the watch target's Frameworks phase (`6451D592ADAB1D3434D501FF` is the `AlmanacWatch` Frameworks phase; confirm by finding the phase listed under the target `E4EB944CA1B663800B89D15C`), a `packageProductDependencies` entry, and an `XCSwiftPackageProductDependency` object with `productName = Motion`.

Verify: `xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' build 2>&1 | grep -E "error:|BUILD"` after Step 3.

- [ ] **Step 2: Delegate and app**

Create `AlmanacWatch/WatchAppDelegate.swift`:

```swift
import WatchKit
import HealthKit

/// The phone starts a workout here: watchOS launches the app and hands the
/// configuration to this delegate.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    static var pendingConfiguration: HKWorkoutConfiguration?
    static var onConfiguration: ((HKWorkoutConfiguration) -> Void)?

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        if let handler = Self.onConfiguration { handler(workoutConfiguration) }
        else { Self.pendingConfiguration = workoutConfiguration }
    }
}
```

In `AlmanacWatchApp.swift`: add `import HealthKit`; inside `AlmanacWatchApp` add `@WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate` and `@State private var workout = WatchWorkoutController()`; wrap the `WindowGroup` content in a `NavigationStack` that shows `WatchWorkoutScreen(workout: workout)` when `workout.state != .idle`, else `WatchDashboard(bridge: bridge, onStartWorkout: { type in workout.start(type: type) })`. In `.task`, add:

```swift
                    WatchAppDelegate.onConfiguration = { configuration in Task { @MainActor in workout.start(configuration) } }
                    if let pending = WatchAppDelegate.pendingConfiguration { WatchAppDelegate.pendingConfiguration = nil; workout.start(pending) }
```

`WatchDashboard` gains `var onStartWorkout: (HKWorkoutActivityType) -> Void = { _ in }` and, above the Refresh button, a menu: `Menu { ForEach(WatchWorkoutController.startable, id: \.type) { Button($0.name) { onStartWorkout($0.type) } } } label: { Label("Start workout", systemImage: "figure.run") }.tint(.orange)`.

- [ ] **Step 3: Controller and screen**

Create `AlmanacWatch/WatchWorkoutController.swift`:

```swift
import Foundation
import HealthKit
import CoreMotion
import AppSurfaces
import Motion

/// Runs the workout on the wrist and mirrors it to the phone. Heart rate and
/// energy come from the live builder; reps from `RepCounter` on device
/// motion for strength. Packets go out once a second and on every rep.
@MainActor @Observable
final class WatchWorkoutController: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    enum State { case idle, running, paused, ending }
    static let startable: [(name: String, type: HKWorkoutActivityType)] = [
        ("Walk", .walking), ("Run", .running), ("Cycle", .cycling), ("Strength", .traditionalStrengthTraining), ("Yoga", .yoga), ("Other", .other)]

    private(set) var state: State = .idle
    private(set) var activityName = ""
    private(set) var startedAt: Date?
    private(set) var heartRate: Int?
    private(set) var energyKcal: Double?
    private(set) var reps: Int?
    private(set) var setIndex: Int?
    private(set) var completedSets: [Int] = []
    private(set) var maxHeartRate: Int?
    var isStrength: Bool { session?.workoutConfiguration.activityType == .traditionalStrengthTraining }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let motion = CMMotionManager()
    private var counter = RepCounter()
    private var lastPacketAt: Date = .distantPast

    func start(type: HKWorkoutActivityType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown
        start(configuration)
    }

    func start(_ configuration: HKWorkoutConfiguration) {
        guard state == .idle else { return }
        activityName = Self.startable.first { $0.type == configuration.activityType }?.name ?? "Other"
        Task {
            do {
                let types: Set<HKSampleType> = [HKObjectType.workoutType(), .quantityType(forIdentifier: .heartRate)!, .quantityType(forIdentifier: .activeEnergyBurned)!]
                try await healthStore.requestAuthorization(toShare: types, read: types)
                let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
                session.delegate = self; builder.delegate = self
                self.session = session; self.builder = builder
                let started = Date.now
                startedAt = started
                session.startActivity(with: started)
                try await builder.beginCollection(at: started)
                try await session.startMirroringToCompanionDevice()
                state = .running
                if isStrength { reps = 0; setIndex = 1; completedSets = []; startMotion() }
                sendPacket(force: true)
            } catch {
                state = .idle; self.session = nil; self.builder = nil
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() {
        guard state != .ending, let session else { return }
        state = .ending
        stopMotion()
        session.stopActivity(with: .now)
    }
    func addRep() { guard isStrength else { return }; reps = (reps ?? 0) + 1; sendPacket(force: true) }
    func nextSet() {
        guard isStrength else { return }
        completedSets.append(reps ?? 0); reps = 0; setIndex = (setIndex ?? 1) + 1
        counter.reset(); sendPacket(force: true)
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        counter.reset()
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, self.state == .running else { return }
            let acceleration = data.userAcceleration
            if self.counter.add(RepCounter.Sample(t: data.timestamp, x: acceleration.x, y: acceleration.y, z: acceleration.z)) {
                self.reps = self.counter.reps
                self.sendPacket(force: true)
            }
        }
    }
    private func stopMotion() { motion.stopDeviceMotionUpdates() }

    private func sendPacket(force: Bool) {
        guard let session, state != .idle else { return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastPacketAt) >= 1 else { return }
        lastPacketAt = now
        var packet = WatchPacket(sentAt: now)
        packet.heartRate = heartRate; packet.heartRateAt = heartRate == nil ? nil : now
        packet.energyKcal = energyKcal
        if isStrength { packet.reps = reps; packet.setIndex = setIndex; packet.completedSets = completedSets }
        guard let data = try? WatchWire.encode(packet) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    private func handle(_ envelope: PhoneCommandEnvelope) {
        switch envelope.command {
        case .configure: maxHeartRate = envelope.maxHeartRate
        case .pause: pause()
        case .resume: resume()
        case .end: end()
        case .nextSet: nextSet()
        case .addRep: addRep()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: self.state = .running
            case .paused: self.state = .paused
            case .stopped:
                do { try await self.builder?.endCollection(at: date); _ = try await self.builder?.finishWorkout() } catch {}
                workoutSession.end()
            case .ended:
                self.state = .idle; self.session = nil; self.builder = nil
                self.heartRate = nil; self.energyKcal = nil; self.reps = nil; self.setIndex = nil; self.completedSets = []
            default: break
            }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.state = .idle; self.session = nil; self.builder = nil }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteDevice data: [Data]) {
        Task { @MainActor in for item in data { if let envelope = WatchWire.command(from: item) { self.handle(envelope) } } }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let type = type as? HKQuantityType, let stats = workoutBuilder.statistics(for: type) else { continue }
                switch type.identifier {
                case HKQuantityTypeIdentifier.heartRate.rawValue:
                    self.heartRate = stats.mostRecentQuantity().map { Int($0.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
                case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                    self.energyKcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
                default: break
                }
            }
            self.sendPacket(force: false)
        }
    }
}
```

Create `AlmanacWatch/WatchWorkoutScreen.swift`:

```swift
import SwiftUI

struct WatchWorkoutScreen: View {
    @Bindable var workout: WatchWorkoutController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(workout.activityName).font(.headline)
                if let startedAt = workout.startedAt, workout.state == .running {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                } else {
                    Text(workout.state == .paused ? "Paused" : "Ending…").font(.title3)
                }
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(workout.heartRate.map(String.init) ?? "—").font(.title2.monospacedDigit())
                    if let max = workout.maxHeartRate, let bpm = workout.heartRate {
                        Text("Z\(zone(bpm: bpm, max: max))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if workout.isStrength {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(workout.reps ?? 0)").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("reps · auto").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Set \(workout.setIndex ?? 1)").font(.caption)
                    }
                    HStack {
                        Button("+1") { workout.addRep() }
                        Button("Next set") { workout.nextSet() }
                    }.tint(.orange)
                }
                HStack {
                    if workout.state == .paused { Button("Resume") { workout.resume() } }
                    else { Button("Pause") { workout.pause() } }
                    Button("End", role: .destructive) { workout.end() }
                }
            }.padding(.horizontal, 4)
        }
        .navigationTitle("Workout")
    }

    private func zone(bpm: Int, max: Int) -> Int {
        let fraction = Double(bpm) / Double(max)
        switch fraction { case ..<0.5: return 0; case ..<0.6: return 1; case ..<0.7: return 2; case ..<0.8: return 3; case ..<0.9: return 4; default: return 5 }
    }
}
```

The zone bands duplicate `HeartRateZones` because the watch does not link `Integrations`; the constants are the five band starts from spec 3.1 of slice 1 and nothing else.

- [ ] **Step 4: Build both targets**

Run the watch build and the app build. Expected: `** BUILD SUCCEEDED **` for both. If `startMirroringToCompanionDevice()` is not `async throws` in the SDK, use the completion form `session.startMirroringToCompanionDevice { _, _ in }`; note the deviation in the report.

- [ ] **Step 5: Commit**

```bash
git add AlmanacWatch LIfeOS.xcodeproj/project.pbxproj
git commit -m "feat(watch): run and mirror the workout from the wrist

HealthKit session and live builder on the watch, mirrored to the phone,
with reps from wrist motion for strength, a minimal workout screen, and
a Start menu on the dashboard. The watch gains HealthKit, the workout
background mode and motion access."
```

---

### Task 6: Reps on the phone surfaces

**Files:**
- Modify: `LIfeOS/Features/Activity/View/SessionHUD.swift`, `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`, `AlmanacWidgets/WorkoutLiveActivity.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`

- [ ] **Step 1: HUD**

In `SessionHUD.swift`:
- Add `var onAddRep: () -> Void = {}` and `var onNextSet: () -> Void = {}` after `showsTimer`.
- Replace `reading(symbol: "repeat", value: nil, chip: "reps", tint: nil)` with `reading(symbol: "repeat", value: readout.repsText, chip: "reps", tint: nil)`.
- In `expanded`, after the existing `HStack`, add for strength:

```swift
            if activity == .strength {
                HStack(spacing: 10) {
                    Text(setLine).font(LifeOSType.caption).foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    Spacer()
                    Button("+1", action: onAddRep).buttonStyle(.glass)
                    Button("Next set", action: onNextSet).buttonStyle(.glass)
                }.font(LifeOSType.label)
            }
```

with `private var setLine: String { [readout.setText, readout.repsText.map { "\($0) reps · auto" }].compactMap { $0 }.joined(separator: " · ") }`.
- In `summary`, append `if activity == .strength, let reps = readout.reps { parts.append("\(reps) reps in set \(readout.setIndex ?? 1)") }`.
- The nested `Button`s inside the outer `Button` label: SwiftUI routes taps to the innermost button, so +1 and Next set work without toggling the capsule.

- [ ] **Step 2: Begin Activity**

In `BeginActivityScreen.liveHero`, pass `onAddRep: { model.addRep() }, onNextSet: { model.nextSet() }` to `SessionHUD`. In `liveTiles`, after the effort tile add:

```swift
                if model.selection == .strength {
                    glassTile(icon: "repeat", label: readout.setText ?? "Reps", value: readout.repsText, unit: "reps",
                              caption: model.completedSets.isEmpty ? "Counted from your wrist · auto" : "Sets so far: \(model.completedSets.map(String.init).joined(separator: ", "))")
                }
```

Change the heart-rate tile caption: `fresh ? (model.source == .watch ? "From Apple Watch" : "Live sensor reading") : ...`. In `connections`, add above the sensor status: `Text(model.source == .watch ? "Apple Watch is recording this session." : WatchSessionBridge.watchAvailable ? "Apple Watch ready" : "Apple Watch not nearby").font(LifeOSType.caption).foregroundStyle(.secondary)`, and replace the "Apple Health:" disclosure sentence with: `Text("Apple Watch: when your watch is nearby it records the workout and counts reps; otherwise this iPhone records.")`.

- [ ] **Step 3: Live Activity**

In `WorkoutLiveActivity.swift`: the compact trailing region becomes `if let reps = readout.repsText { Text("\(reps) reps").font(.caption.monospacedDigit()).frame(width: 60) } else { WorkoutTimer(...) }`; the expanded bottom status line gains `if let set = readout.setText, let reps = readout.repsText { Text("\(set) · \(reps) reps") }` before the "Open activity" link; the lock screen's KCAL tile becomes `Tile(eyebrow: readout.setText?.uppercased() ?? "KCAL", value: readout.repsText ?? readout.caloriesText, symbol: readout.reps == nil ? "flame.fill" : "repeat")`.

- [ ] **Step 4: Fixture and captures**

In `HealthActivityDesignPreview`'s `--live --strength` path, after the readings loop add `fixture.recorder.addRep(); fixture.recorder.addRep(); fixture.recorder.nextSet(); fixture.recorder.addRep()` so the capture shows "Set 2 · 1 reps". Build, capture `docs/design/watch-companion/session-strength-iphone.png` (portrait, `--design-preview --page=activity --live --strength`) and, with `--live-activity`, the lock screen as in the slice 1 plan. Inspect both with the Read tool: the HUD reads "1 reps", the tile reads "Set 2", the lock screen tile three reads "SET 2 / 1".

- [ ] **Step 5: Build and commit**

Build the app scheme. Expected: `** BUILD SUCCEEDED **`.

```bash
git add LIfeOS/Features AlmanacWidgets docs/design/watch-companion
git commit -m "feat(activity): show reps and sets on every surface

The strength slot fills: reps and set on the HUD with +1 and Next set,
a reps tile, the Dynamic Island's compact side, and the lock screen tile.
Begin Activity says which device is recording."
```

---

### Task 7: Hardware report and spec status

**Files:**
- Create: `docs/design/watch-companion/report.md`
- Modify: `docs/superpowers/specs/2026-09-14-watch-companion-design.md`

- [ ] **Step 1: Run the five hardware checks** from spec section 8 on Shiv's iPhone and watch (run both targets from Xcode on the devices). Record each outcome with a sentence and, where possible, a photo or screenshot in the folder. If the developer running this plan cannot access the devices, write each as "Pending: to be run by Shiv" with the steps.

- [ ] **Step 2: Write the report** following `design-qa.md`'s section order, referencing every capture, pasting the full checks output (fifteen from slice 1 plus the five new lines), the package test total, and the hardware outcomes. Note the rep-counter constants in force and any tuning done.

- [ ] **Step 3: Update the spec status** to `**Status:** implemented on feat/watch-companion, see docs/design/watch-companion/report.md` and record in section 9 whether `recoverActiveWorkoutSession` returned the mirrored session on hardware.

- [ ] **Step 4: Full verification and commit**

Run `cd LifeOSKit && swift test 2>&1 | tail -2` (all pass), both builds, the checks page.

```bash
git add docs
git commit -m "docs(watch): QA report for the watch companion"
```

## Self-review

**Spec coverage.** 3.1 source choice, hand-off, timeout, watch-started sessions, draft: Task 4 (adoptMirroredSession, start block) and Task 3 (draft). 3.2 watch controller and phone bridge: Tasks 5 and 4. 3.3 wire format: Task 1. 4 rep counter, target, sets: Tasks 2, 3, 5. 5 recorder changes and readout fields: Tasks 1, 3, 4. 6 surfaces: Task 6. 7 watch capabilities: Task 5. 8 tests and hardware: Tasks 1 to 4, 7. 9 risks: the mirroring handler is installed at launch in Task 4; the Live Activity is requested by the recorder's first `persist()` in `adoptMirroredSession`.

**Placeholders.** None: the pbxproj additions describe exact entries; hardware steps are explicit and may be marked pending by name.

**Type consistency.** `WatchPacket(sentAt:)`, `PhoneCommandEnvelope(command:sentAt:maxHeartRate:)`, `WatchWire.encode/packet(from:)/command(from:)`, `RepCounter.Sample(t:x:y:z:)`, `SessionSource`, `LiveReadoutBuilder.readout(... reps:setIndex:)`, `WatchSessionBridge.send(_:maxHeartRate:)`, `ActivityRecorder.receiveWatchPacket(_:)`, `addRep()`, `nextSet()`, `watchAvailable`, `watchHandoffTimeout`, `SessionHUD(onAddRep:onNextSet:)` are used with the same names in every task.
