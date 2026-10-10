# Focus Experience in LifeOS Focus (Slice 3b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give LifeOS Focus the real focus experience: a Home with this
week's time, the four moods, Resume last and recent sessions, and the
existing setup sheet, session screen, soundscape, Apple Music and summary.
LifeOS keeps working on the same code.

**Architecture:**
- **A shared module.** `LIfeOS/Features/Focus` moves into a new `LifeOSKit`
  module, `FocusExperience`, which is iOS-only. The three things it used to
  reach into the LifeOS app for become **host hooks** that each app supplies:
  - gathering mood inputs (weather and recovery)
  - saying a session was saved (sync)
  - an optional heart-rate source (the LifeOS watch)
- **Each app adds its own.** LifeOS passes its existing behaviour. The Focus
  app gets a real Home, its own sync driver and the audio Info.plist keys.
- **Later slices.** Slice 5 later removes LifeOS's focus screens. Slice 3c
  adds the HealthKit and WeatherKit inputs, the watch and the widget.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation, MusicKit,
MediaPlayer, Swift Testing, XCUITest, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-10-10-lifeos-focus-app-design.md`
(section 1, "What moves where"; section 3, Home, setup, session and
Settings).

## Spec amendment

The spec moves `LIfeOS/Features/Focus` into the `LifeOSFocus` target. LifeOS
keeps its focus screens until slice 5, so moving the code into one target
would leave two copies that drift apart. **This plan moves it into the shared
module `FocusExperience` instead.** Both apps import it, and slice 5 simply
stops LifeOS from presenting it. Shiv approved this on 2026-10-11.

## Global Constraints

- iOS 26.0. `FocusExperience` is iOS-only: wrap every source file in `#if os(iOS)` … `#endif`, because the package also builds for macOS and watchOS.
- No behaviour change in LifeOS. The existing `FocusUITests` (2 tests) must stay green.
- Use DesignSystem tokens only. `zsh scripts/check-typography.sh` must report nothing new in `LifeOSKit/Sources/FocusExperience` or `LifeOSFocus/`.
- No AI attribution in commits, no em dashes, and conventional commits. Work on branch `feat/focus-experience`, stacked on `feat/focus-app`.
- Disk is tight (about 11 GB free). Use `-derivedDataPath /tmp/claude-501/<name>` for simulator builds and delete it afterwards.
- Use the private simulator `FocusApp iPhone 17` (`268EE00E-3389-43B2-A1C7-D78EBE5AFA77`).

## Review Focus

1. **A session saved in either app must trigger that app's sync.** A missed hook means sessions never leave the phone. Test: Task 2, in `FocusHooksTests`, `sessionSavedHookRunsOnEnd`.
2. **Focus app with no mood inputs.** Until slice 3c, the Focus app's `gatherInputs` returns empty inputs. The composer must still produce a soundscape, which it does today when an input is nil. Covered by the existing `SoundscapeTests` plus the Task 4 simulator run.
3. **A session left running when the app was killed.** Restore must resume or summarise it in both apps. This is `FocusSessionModel.restore(context:)` after the hook change. Covered by the existing LifeOS `FocusUITests`, and in Focus by Task 4's screenshot of a resumed session.
4. **The "Resume last" button with no previous session.** It opens setup with the default mood, today's behaviour. Test: Task 3, `recentIsEmptyForANewStore`, plus the Home code path.
5. **Recent sessions on Home exclude unfinished sessions and are newest first.** Test: Task 3, `recentIsNewestFirstAndFinishedOnly`.

---

## File Structure

| From | To | Notes |
|---|---|---|
| `LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift` | `LifeOSKit/Sources/FocusExperience/FocusSessionModel.swift` | Gains `hooks: FocusHooks`. `restore(context:providers:)` becomes `restore(context:)`. `FocusSyncDriver.shared.request()` becomes `hooks.sessionSaved()` |
| `LIfeOS/Features/Focus/Model/{SoundscapeEngine,MusicSource,FocusNotifications,FocusNowPlaying,FocusLauncher}.swift` | `LifeOSKit/Sources/FocusExperience/` | Moved, and made `public` where used from outside |
| `LIfeOS/Features/Focus/Model/FocusInputs.swift` | Split | `struct FocusInputs` moves to the module. LifeOS's `gather(context:providers:)` stays in the app as `LifeOSFocusInputs.gather` |
| `LIfeOS/Features/Focus/Model/FocusHeartRate.swift` | Stays in LifeOS | Conforms to the new `FocusHeartRateSource` |
| `LIfeOS/Features/Focus/View/{FocusSessionScreen,FocusSetupSheet,FocusSummaryView,FocusVisual}.swift` | `LifeOSKit/Sources/FocusExperience/` | Made `public` where used from outside |
| `LIfeOS/Features/Focus/View/FocusDesignPreview.swift`, `Intents/StartFocusSessionIntent.swift` | Stay in LifeOS | Add `import FocusExperience` |
| (new) `LifeOSKit/Sources/FocusExperience/FocusHooks.swift` | Create | `FocusHooks`, `FocusHeartRateSource` |
| (new) `LifeOSKit/Tests/FocusExperienceTests/FocusHooksTests.swift` | Create | The hooks fire |
| `LifeOSKit/Sources/Persistence/FocusSessionRecord.swift` | Modify | `FocusStore.recent(limit:)`, `focusedSeconds(inWeekOf:)` |
| `LifeOSFocus/FocusHomeView.swift` | Rewrite | The real Home |
| `LifeOSFocus/FocusSession.swift` | Create | Owns the model, the container, the sync driver and the presentation |
| `LifeOSFocus/Info.plist` | Modify | `UIBackgroundModes` audio, `NSAppleMusicUsageDescription` |
| `LIfeOS/App/RootView.swift`, `LIfeOS/Features/Today/View/TodayModules.swift`, `LIfeOS/Features/Projects/View/TaskSheet.swift` | Modify | `import FocusExperience`, and the hooks |

---

### Task 1: Create `FocusExperience` and move the non-UI code

**Files:** the module target, `FocusHooks.swift`, the five model files, `FocusInputs`, `FocusSessionModel`, and their LifeOS call sites.

**Interfaces:**
- Produces:
  - `public struct FocusHooks`, with:
    - `public var gatherInputs: @MainActor (ModelContext) async -> FocusInputs`
    - `public var sessionSaved: @MainActor () -> Void`
    - `public var heartRate: (any FocusHeartRateSource)?`
    - `public init(gatherInputs:sessionSaved:heartRate:)`
    - `public static let none` (empty inputs, no-op saved, no heart rate)
  - `@MainActor public protocol FocusHeartRateSource: AnyObject`, with
    `var onHeartRate: ((Int) -> Void)? { get set }`, `func start() async`
    and `func stop()`
  - `public struct FocusInputs` (same fields, now public)
  - `@MainActor @Observable public final class FocusSessionModel`, with
    `public init(defaults: UserDefaults = .standard, notifies: Bool = true, hooks: FocusHooks = .none)`
    and `public func restore(context: ModelContext) async`. The other members
    LifeOS uses become public.
  - `public final class FocusLauncher` with `public static let shared`,
    `public struct Request` and `public func open(mood:taskID:taskTitle:)`

- [ ] **Step 1: Write the failing test**

```swift
// LifeOSKit/Tests/FocusExperienceTests/FocusHooksTests.swift
#if os(iOS)
import Testing
import Foundation
import SwiftData
import Persistence
import Soundscape
@testable import FocusExperience

@MainActor
struct FocusHooksTests {
    @Test func sessionSavedHookRunsOnEnd() async throws {
        let container = try LifeOSContainer.make(inMemory: true)
        defer { withExtendedLifetime(container) {} }
        var saved = 0
        let hooks = FocusHooks(gatherInputs: { _ in FocusInputs() }, sessionSaved: { saved += 1 }, heartRate: nil)
        let model = FocusSessionModel(defaults: UserDefaults(suiteName: "focus.hooks.\(UUID())")!, notifies: false, hooks: hooks)
        await model.start(FocusSetup(mood: .focus, preset: .pomodoro, source: .silence), inputs: FocusInputs(),
                          context: container.mainContext)
        model.end()
        #expect(saved == 1)
    }
}
#endif
```

Check `FocusSetup`'s initializer labels with
`grep -n "public init" LifeOSKit/Sources/Soundscape/FocusSetup.swift`, and
use them exactly. If no preset is named `.pomodoro`, use the first case of
`TimerPreset`.

Add the targets to `Package.swift`:

```swift
        .library(name: "FocusExperience", targets: ["FocusExperience"]),
        .target(name: "FocusExperience", dependencies: ["DesignSystem", "Persistence", "Soundscape", "AppSurfaces"]),
        .testTarget(name: "FocusExperienceTests", dependencies: ["FocusExperience", "Persistence", "Soundscape"]),
```

- [ ] **Step 2: Run it and confirm it fails**

The module is iOS-only, so `swift test` on macOS compiles it to nothing. Run
the test on the simulator:

```bash
cd LifeOSKit && xcodebuild test -scheme LifeOSKit-Package -destination 'id=268EE00E-3389-43B2-A1C7-D78EBE5AFA77' \
  -only-testing:FocusExperienceTests -derivedDataPath /tmp/claude-501/kit-dd -quiet 2>&1 | grep -E "error:|Executed|passed|failed" | tail -5
```

Expected: a compile failure, "cannot find 'FocusHooks'". If the scheme is
named differently, list the schemes with `xcodebuild -list` and ledger the
name you used.

- [ ] **Step 3: Move and adapt**

Move the files with `git mv`, into `LifeOSKit/Sources/FocusExperience/`:
- `LIfeOS/Features/Focus/ViewModel/FocusSessionModel.swift`
- `LIfeOS/Features/Focus/Model/SoundscapeEngine.swift`
- `LIfeOS/Features/Focus/Model/MusicSource.swift`
- `LIfeOS/Features/Focus/Model/FocusNotifications.swift`
- `LIfeOS/Features/Focus/Model/FocusNowPlaying.swift`
- `LIfeOS/Features/Focus/Model/FocusLauncher.swift`

Wrap each one in `#if os(iOS)` / `#endif`.

Write `FocusHooks.swift`:

```swift
#if os(iOS)
import Foundation
import SwiftData

/// What a focus session needs from the app running it. LifeOS gathers its
/// inputs from WHOOP and its weather provider and has a watch for heart
/// rate; LifeOS Focus has neither yet. Each app also syncs its own way.
public struct FocusHooks {
    public var gatherInputs: @MainActor (ModelContext) async -> FocusInputs
    public var sessionSaved: @MainActor () -> Void
    public var heartRate: (any FocusHeartRateSource)?

    public init(gatherInputs: @escaping @MainActor (ModelContext) async -> FocusInputs,
                sessionSaved: @escaping @MainActor () -> Void,
                heartRate: (any FocusHeartRateSource)?) {
        self.gatherInputs = gatherInputs
        self.sessionSaved = sessionSaved
        self.heartRate = heartRate
    }

    public static let none = FocusHooks(gatherInputs: { _ in FocusInputs() }, sessionSaved: {}, heartRate: nil)
}

/// A live heart rate during a session (LifeOS: the paired watch).
@MainActor
public protocol FocusHeartRateSource: AnyObject {
    var onHeartRate: ((Int) -> Void)? { get set }
    func start() async
    func stop()
}
#endif
```

Write `FocusInputs.swift` in the module, holding the struct only:

```swift
#if os(iOS)
import Soundscape

public struct FocusInputs {
    public var weather: WeatherInput?
    public var recovery: RecoveryLevel?
    public var restingHeartRate: Double?
    public init(weather: WeatherInput? = nil, recovery: RecoveryLevel? = nil, restingHeartRate: Double? = nil) {
        self.weather = weather; self.recovery = recovery; self.restingHeartRate = restingHeartRate
    }
}
#endif
```

In LifeOS, rename what is left of `LIfeOS/Features/Focus/Model/FocusInputs.swift`
to `LifeOSFocusInputs.swift`, holding
`enum LifeOSFocusInputs { static func gather(context: ModelContext, providers: DayProviders?) async -> FocusInputs { … } }`.
Its body is the old `gather`, unchanged.

In `FocusSessionModel`, make these changes:
- Add `private let hooks: FocusHooks`, and the `hooks` init parameter (default `.none`).
- Replace `private let watch = FocusHeartRate()` with `hooks.heartRate`, via `private var watch: (any FocusHeartRateSource)? { hooks.heartRate }`. Optional-chain its calls: `watch?.onHeartRate = …`, `await watch?.start()` and `watch?.stop()`.
- Replace both `FocusSyncDriver.shared.request()` calls with `hooks.sessionSaved()`.
- Change `restore(context:providers:)` to `restore(context:)`, and replace `FocusInputs.gather(context: context, providers: providers)` with `await hooks.gatherInputs(context)`.
- Make public: the class, `init`, `start`, `restore`, `pause`, `resume`, `skip`, `changeMood`, `end`, `markTaskDone`, `dismissSummary`, `resumeSound`, `phaseTitle`, and every property `FocusSessionScreen`, `FocusSummaryView` or `RootView` reads. The compiler errors in Step 4 list exactly which.

In `FocusHeartRate.swift` (LifeOS), declare
`final class FocusHeartRate: FocusHeartRateSource` and add
`import FocusExperience`.

In `RootView.swift`, build the model with LifeOS's hooks. Find
`FocusSessionModel(` with `grep -n "FocusSessionModel(" LIfeOS/App/RootView.swift`.

```swift
FocusSessionModel(hooks: FocusHooks(
    gatherInputs: { context in await LifeOSFocusInputs.gather(context: context, providers: nil) },
    sessionSaved: { FocusSyncDriver.shared.request() },
    heartRate: FocusHeartRate()))
```

The `providers: nil` is temporary: `dayProviders` is an instance property of
`RootView`, so the closure must capture it. If `focus` is a `@State`
initialised inline, move the hooks into a `.task` that calls a new
`focus.setHooks(_:)`. If it is built in `init`, pass `dayProviders` there.
Ledger whichever you do. **LifeOS must still pass `dayProviders`, so the
weather input keeps working.**

Then:
- Replace `.task { await focus.restore(context: context, providers: dayProviders) }` with `.task { await focus.restore(context: context) }`.
- Replace `FocusInputs.gather(context: context, providers: dayProviders)` in the setup sheet's `onStart` with `LifeOSFocusInputs.gather(context: context, providers: dayProviders)`.
- Add `import FocusExperience` to `RootView.swift`, `TodayModules.swift`, `TaskSheet.swift`, `StartFocusSessionIntent.swift` and `FocusDesignPreview.swift`, and to any other file the build names.
- Add the `FocusExperience` product to the `LIfeOS` target. Copy the pbxproj pattern for `FocusSync` (search for `F0C05001`), using new ids `F0CE0001F0CE0001F0CE0001` and `F0CE0002F0CE0002F0CE0002`. The count check is 6 mentions.

- [ ] **Step 4: Build until clean**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' -quiet > /tmp/claude-501/b.log 2>&1; echo exit=$?
grep error: /tmp/claude-501/b.log | sort -u | head -20
```

For every "is inaccessible due to 'internal' protection level", make that
member `public`. Repeat until you get `exit=0`.

- [ ] **Step 5: Run the hook test, and the LifeOS focus UI tests**

Rerun Step 2's command. Expected: `FocusHooksTests` passes.

```bash
xcodebuild test -project LIfeOS.xcodeproj -scheme LIfeOSUITests -destination 'id=268EE00E-3389-43B2-A1C7-D78EBE5AFA77' \
  -only-testing:LIfeOSUITests/FocusUITests -derivedDataPath /tmp/claude-501/ui-dd -quiet 2>&1 | grep -E "error:|Executed" | tail -2
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A LifeOSKit LIfeOS LIfeOS.xcodeproj
git commit -m "refactor(focus): move the focus session model into FocusExperience

The model, sound engine, Apple Music, notifications, now playing and the
launcher move into a shared iOS module so LifeOS Focus can run them. The
three things the model reached into the app for become hooks: inputs,
a saved-session signal for sync, and an optional heart-rate source."
```

### Task 2: Move the focus views

**Files:** `FocusSessionScreen.swift`, `FocusSetupSheet.swift`, `FocusSummaryView.swift` and `FocusVisual.swift`, from `LIfeOS/Features/Focus/View/` to `LifeOSKit/Sources/FocusExperience/`.

**Interfaces:**
- Produces:
  - `public struct FocusSetupSheet: View`, with
    `public init(initial: FocusSetup, preferences: FocusPreferences, taskTitle: String?, onStart: @escaping (FocusSetup) -> Void)`
  - `public struct FocusSessionScreen: View`, with
    `public init(model: FocusSessionModel)`

- [ ] **Step 1: Move them**

Move the four files with `git mv`, and wrap each in `#if os(iOS)`. Make the
two views and their inits `public`, and make anything they need from each
other at least `internal`. Leave `FocusDesignPreview.swift` in LifeOS.

- [ ] **Step 2: Build, then run the regression tests**

Run Task 1's Step 4 build, then Task 1's Step 5 commands.

Expected: build `exit=0`, `FocusHooksTests` passes, and `FocusUITests`
passes 2/2.

Also run
`zsh scripts/check-typography.sh | grep -c FocusExperience`, and compare it
with the count on `HEAD~1` for the same files under their old path. The
count must not go up: moving code must not add new typography findings.
Ledger both numbers.

- [ ] **Step 3: Commit**

```bash
git add -A LifeOSKit LIfeOS
git commit -m "refactor(focus): move the focus screens into FocusExperience"
```

### Task 3: What Home reads from the store

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/FocusSessionRecord.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift`

**Interfaces:**
- Produces:
  - `FocusStore.recent(limit: Int = 10) throws -> [FocusSessionSnapshot]`:
    finished sessions only, newest first
  - `FocusStore.focusedSeconds(inWeekOf day: Date, calendar: Calendar = .current) throws -> TimeInterval`:
    excludes sleep, like `focusedSeconds(on:)`

- [ ] **Step 1: Write the failing tests**

Add to `FocusStoreTests`, using its `Self.day` and `Self.utc` helpers:

```swift
    @MainActor @Test func recentIsEmptyForANewStore() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        #expect(try FocusStore(context: container.mainContext).recent().isEmpty)
    }

    @MainActor @Test func recentIsNewestFirstAndFinishedOnly() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day.addingTimeInterval(600),
                         focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "relax", source: "silence", startedAt: Self.day.addingTimeInterval(3600),
                         endedAt: Self.day.addingTimeInterval(4200), focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day.addingTimeInterval(7200), endedAt: nil,
                         focusedSeconds: 0, blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.recent().map(\.mood) == ["relax", "focus"])
    }

    @MainActor @Test func weekTotalSkipsSleepAndOtherWeeks() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day,
                         focusedSeconds: 1200, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "sleep", source: "soundscape", startedAt: Self.day, endedAt: Self.day,
                         focusedSeconds: 3000, blocksCompleted: 0, projectTaskID: nil)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day.addingTimeInterval(-14 * 86_400),
                         endedAt: Self.day.addingTimeInterval(-14 * 86_400), focusedSeconds: 900, blocksCompleted: 1, projectTaskID: nil)
        #expect(try store.focusedSeconds(inWeekOf: Self.day, calendar: Self.utc) == 1200)
    }
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `cd LifeOSKit && swift test --filter FocusStoreTests`
Expected: compile failures, "no member 'recent'" and "no member 'focusedSeconds(inWeekOf:'".

- [ ] **Step 3: Implement**

Add to `FocusStore`:

```swift
    /// Finished sessions, newest first, for a list of recent sessions.
    public func recent(limit: Int = 10) throws -> [FocusSessionSnapshot] {
        var descriptor = FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.snapshot)
    }

    /// Focused time in the calendar week containing `day`. Sleep is rest,
    /// not focus, as on the day total.
    public func focusedSeconds(inWeekOf day: Date, calendar: Calendar = .current) throws -> TimeInterval {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return 0 }
        let start = week.start, end = week.end
        let descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate {
            $0.startedAt >= start && $0.startedAt < end && $0.mood != "sleep"
        })
        return try context.fetch(descriptor).reduce(0) { $0 + $1.focusedSeconds }
    }
```

- [ ] **Step 4: Run them and confirm they pass**

Run: `cd LifeOSKit && swift test --filter FocusStoreTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/FocusSessionRecord.swift LifeOSKit/Tests/PersistenceTests/FocusStoreTests.swift
git commit -m "feat(focus): recent sessions and the week's focused time"
```

### Task 4: The Focus app's Home and sessions

**Files:**
- Create: `LifeOSFocus/FocusSession.swift`
- Rewrite: `LifeOSFocus/FocusHomeView.swift`
- Modify: `LifeOSFocus/FocusRootView.swift`, `LifeOSFocus/Info.plist`, `scripts/add-focus-target.rb` and the pbxproj (add the `FocusExperience` and `Soundscape` products to `LifeOSFocus`)

**Interfaces:**
- Consumes:
  - `FocusSessionModel`, `FocusHooks`, `FocusSetupSheet`, `FocusSessionScreen` and `FocusInputs` (Tasks 1 and 2)
  - `FocusStore.recent` and `focusedSeconds(inWeekOf:)` (Task 3)
  - `FocusSync(context:remote:owner:session:)`
  - `AccountGate`
- Produces: `@MainActor @Observable final class FocusSession`, with:
  - `init(owner: String)`
  - `let container: ModelContainer`
  - `let model: FocusSessionModel`
  - `var request: FocusLauncher.Request?`
  - `func open(mood: Mood?)`
  - `func syncNow()`

- [ ] **Step 1: Add the products to the target**

In `scripts/add-focus-target.rb`:
- Change `PRODUCTS` to `%w[AccountUI DesignSystem Integrations Persistence FocusSync FocusExperience Soundscape]`.
- Add a block that adds any missing product to an **existing** target: when the target exists, loop over `PRODUCTS`, and for each name not already in `target.package_product_dependencies.map(&:product_name)`, add the dependency and its build file exactly as the creation path does. Then save and print `"updated #{NAME}"`, in place of exiting early.

Run `ruby scripts/add-focus-target.rb`. Expected: `updated LifeOSFocus`.
Run it again. Expected: no change to `project.pbxproj` (check with
`git diff --stat` before and after).

- [ ] **Step 2: Add the Info.plist keys**

Add inside the `<dict>`:

```xml
	<key>UIBackgroundModes</key>
	<array><string>audio</string></array>
	<key>NSAppleMusicUsageDescription</key>
	<string>LifeOS Focus plays music from your Apple Music library during a focus session.</string>
```

- [ ] **Step 3: Write `FocusSession.swift`**

```swift
import Foundation
import SwiftData
import FocusExperience
import FocusSync
import Integrations
import Persistence
import Soundscape

/// Everything a signed-in Focus app runs: its store, the session model, and
/// the sync that sends sessions to the account LifeOS also reads.
@MainActor @Observable
final class FocusSession {
    let container: ModelContainer
    let model: FocusSessionModel
    var request: FocusLauncher.Request?
    private let sync: FocusSync?

    init(owner: String) {
        // The Focus app's own store, in its own sandbox. Same schema as
        // LifeOS, so FocusStore and FocusSync work unchanged.
        container = (try? LifeOSContainer.make()) ?? (try! LifeOSContainer.make(inMemory: true))
        if let url = FocusConfig.supabaseURL, let key = FocusConfig.supabaseAnonKey {
            sync = FocusSync(context: container.mainContext, remote: SupabaseREST(baseURL: url, anonKey: key),
                             owner: owner, session: { KeychainAuthSessionStore().load() })
        } else {
            sync = nil
        }
        let sync = self.sync
        // Weather and recovery arrive in slice 3c; until then the composer
        // works without them, as it does whenever an input is missing.
        model = FocusSessionModel(hooks: FocusHooks(
            gatherInputs: { _ in FocusInputs() },
            sessionSaved: { if let sync { Task { await sync.run() } } },
            heartRate: nil))
    }

    func open(mood: Mood?) { request = FocusLauncher.Request(mood: mood) }

    func syncNow() { if let sync { Task { await sync.run() } } }
}
```

Check `FocusLauncher.Request`'s init. If it has no public memberwise init,
add one in the module:
`public init(mood: Mood? = nil, taskID: UUID? = nil, taskTitle: String? = nil)`.

- [ ] **Step 4: Rewrite Home**

```swift
import SwiftUI
import SwiftData
import AccountUI
import DesignSystem
import FocusExperience
import Persistence
import Soundscape

/// Home: the week's focus as the masthead figure, a mood to start in one tap,
/// Resume last, and the sessions so far.
struct FocusHomeView: View {
    let gate: AccountGate
    @Bindable var session: FocusSession
    @Environment(\.colorScheme) private var scheme
    @State private var weekSeconds: TimeInterval = 0
    @State private var recent: [FocusSessionSnapshot] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                EditorialMasthead(eyebrow: "LifeOS Focus · This week", title: Self.duration(weekSeconds),
                                  detail: "Signed in as \(account).")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.x1) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        Button(mood.title) { session.open(mood: mood) }
                            .buttonStyle(.editorial(.primary, fullWidth: true))
                    }
                }
                Button("Resume last") { session.open(mood: nil) }
                    .buttonStyle(.editorial(.secondary, size: .compact))
                if !recent.isEmpty {
                    EditorialSectionHeader(title: "Recent")
                    VStack(spacing: 0) {
                        ForEach(recent, id: \.id) { row in
                            EditorialRow(title: Mood(rawValue: row.mood)?.title ?? row.mood,
                                         value: Text(Self.duration(row.focusedSeconds)))
                            Hairline()
                        }
                    }
                }
                Button("Sign out") { gate.signOut() }
                    .buttonStyle(.editorial(.quiet, size: .compact))
            }
            .padding(Space.x3)
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .sheet(item: $session.request) { request in
            let mood = request.mood ?? session.model.preferences.lastMood
            FocusSetupSheet(initial: session.model.preferences.setup(for: mood),
                            preferences: session.model.preferences, taskTitle: nil) { setup in
                Task {
                    await session.model.start(setup, inputs: FocusInputs(), context: session.container.mainContext)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { session.model.isPresented }, set: { _ in })) {
            FocusSessionScreen(model: session.model)
        }
        .task { await session.model.restore(context: session.container.mainContext); reload() }
        .onChange(of: session.model.isPresented) { _, presented in if !presented { reload() } }
    }

    private func reload() {
        let store = FocusStore(context: session.container.mainContext)
        weekSeconds = (try? store.focusedSeconds(inWeekOf: .now)) ?? 0
        recent = (try? store.recent()) ?? []
        session.syncNow()
    }

    private var account: String { gate.session?.email ?? gate.session?.phone ?? "your account" }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
```

Check the signatures of `EditorialSectionHeader(title:)`,
`EditorialRow(title:value:)` and `.editorial(.primary, fullWidth:)` /
`.quiet` before using them:
`grep -n "public init\|static func editorial\|case quiet\|case primary" LifeOSKit/Sources/DesignSystem/Editorial*.swift`.
Use the real labels, and ledger any difference.

Run the typography check over `LifeOSFocus/` afterwards.

- [ ] **Step 5: Hold the session in the root view**

In `FocusRootView`:
- Add `@State private var focus: FocusSession?`.
- When `gate.isSignedIn`, show `FocusHomeView(gate: gate, session: focusSession())`.
- `focusSession()` returns `focus` if its owner matches `gate.session?.userID`. Otherwise it builds a new `FocusSession(owner:)` and stores it in `focus`, through `.onChange(of: gate.session?.userID, initial: true)`, never in `body`.

Add a DEBUG preview path for screenshots. In `LifeOSFocusApp`, when the
process arguments contain `--design-preview`, show
`FocusHomeView(gate: AccountGate(backend: nil, store: InMemoryAuthSessionStore(session: AuthSession(accessToken: "a", refreshToken: nil, expiresAt: .distantFuture, userID: "preview", phone: nil, email: "preview@lifeos.app", hasProfile: true))), session: FocusSession(owner: "preview"))`
inside `#if DEBUG`.

- [ ] **Step 6: Build, launch and screenshot**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LifeOSFocus -destination 'id=268EE00E-3389-43B2-A1C7-D78EBE5AFA77' \
  -derivedDataPath /tmp/claude-501/focus-dd -quiet > /tmp/claude-501/fb.log 2>&1; echo exit=$?
xcrun simctl boot 268EE00E-3389-43B2-A1C7-D78EBE5AFA77 2>/dev/null
xcrun simctl install 268EE00E-3389-43B2-A1C7-D78EBE5AFA77 /tmp/claude-501/focus-dd/Build/Products/Debug-iphonesimulator/LifeOSFocus.app
xcrun simctl launch 268EE00E-3389-43B2-A1C7-D78EBE5AFA77 com.shivvyas.lifeos.focus --design-preview
sleep 5; xcrun simctl io 268EE00E-3389-43B2-A1C7-D78EBE5AFA77 screenshot <scratchpad>/focus-home.png
```

Expected: Home with "0 min", the four mood buttons and Resume last.

Then check a session by hand. Driving taps from the command line doesn't
work on this machine, so tell Shiv how instead: open the scheme in Xcode,
run, tap Focus, then Start. Ledger that this check is manual.

Delete `/tmp/claude-501/focus-dd`, `/tmp/claude-501/kit-dd` and `/tmp/claude-501/ui-dd`.

- [ ] **Step 7: Make sure LifeOS still builds, then commit and open the PR**

Run the LIfeOS build. Expected: `exit=0`.

```bash
git add -A LifeOSFocus scripts LIfeOS.xcodeproj
git commit -m "feat(focus-app): Home with moods, Resume last and recent sessions, running real sessions"
git push -u origin feat/focus-experience
```

Open a PR against `feat/focus-app` (stacked), titled
"feat(focus-app): the focus experience in LifeOS Focus". Don't merge it.
