# iPad Full Screen and Activity Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the live session and workout video fill an iPad in both orientations, and replace the six-activity enum with the full 79-type Apple Watch activity catalog on the phone and the Watch.

**Architecture:** A data-only `ActivityCatalog` in the dependency-free `AppSurfaces` package feeds the phone recorder, the Watch controller and the Live Activity, so one table replaces three hand-copied ones. The phone keeps a per-account recents list and a searchable picker sheet. iPad gets a full-screen cover for Begin Activity, aspect-based landscape detection in the video screen, and a two-column layout on both live screens at 900 points and up.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, HealthKit, WatchConnectivity, Swift Testing for package tests, the app's DEBUG native check harness (`ActivityRecorderChecks`, run from the design preview with `--design-preview --page=checks`).

**Spec:** `docs/superpowers/specs/2026-09-16-ipad-full-screen-and-activity-catalog-design.md`

## Global Constraints

- Work happens in the worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities` on branch `feat/ipad-and-activity-catalog`. Never `cd` to the main checkout.
- Package tests run with `cd LifeOSKit && swift test --filter <Suite>`; they run on macOS, so `AppSurfaces` must not import HealthKit, UIKit or WatchKit.
- The stored activity name is the display name. `Walk`, `Run`, `Cycle`, `Strength`, `Yoga`, `Other` must keep exactly those spellings.
- Conventional commits, `type(scope): imperative summary`, no em dashes anywhere, no attribution trailers.
- The iOS build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' build`. The Watch build: `xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' build`. The iPad simulator is `LifeOS-iPad13`, id `9CFEE6A6-F8A5-4A50-A8ED-F1C15C322C8E`. Pipe build output to a file in the scratchpad and grep for `error:` and `BUILD`.
- `sleep` is blocked in the Bash tool; wait with `perl -e 'select(undef,undef,undef,SECONDS)'`.

## File Structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/AppSurfaces/ActivityCatalog.swift` (new) | `ActivityType` value and the `ActivityCatalog` table plus lookups. Pure data. |
| `LifeOSKit/Tests/AppSurfacesTests/ActivityCatalogTests.swift` (new) | Package tests for the table and lookups. |
| `LIfeOS/Features/Activity/Model/ActivityType+Health.swift` (new) | `ActivityType.healthType` and the named accessors the app reads (`ActivityCatalog.walk` and friends). |
| `LIfeOS/Features/Activity/Model/ActivityRecents.swift` (new) | Per-account recents list over `UserDefaults`. |
| `LIfeOS/Features/Activity/View/ActivityPickerSheet.swift` (new) | Searchable grouped picker. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift` | `selection: ActivityType`, flags instead of enum cases. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorder+Watch.swift` | Same, on the mirror path. |
| `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift` | New checks 8 to 10 from the spec. |
| `LIfeOS/Features/Activity/View/SessionRings.swift` | Takes flags, not the enum. |
| `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` | Recents grid with More tile; wide layout. |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Uses the catalog accessors. |
| `LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift` | Name lookup for the split; aspect landscape; wide layout. |
| `LIfeOS/App/Surfaces/WatchSessionBridge.swift` | Catalog lookup for the Live Activity name and icon. |
| `LIfeOS/App/RootView.swift` | Full-screen cover for Begin Activity on regular width. |
| `AlmanacWatch/WatchWorkoutController.swift` | Catalog lookup, `isStrength` from the flag. |
| `AlmanacWatch/AlmanacWatchApp.swift` | Grouped start list. |
| `docs/design/widgets-watch/implementation.md` | One paragraph. |
| `docs/design/ipad/` (new) | Screenshots. |

---

### Task 1: The catalog in AppSurfaces

**Files:**
- Create: `LifeOSKit/Sources/AppSurfaces/ActivityCatalog.swift`
- Test: `LifeOSKit/Tests/AppSurfacesTests/ActivityCatalogTests.swift`

**Interfaces:**
- Produces: `public struct ActivityType: Identifiable, Hashable, Sendable` with `name: String`, `group: ActivityType.Group`, `symbol: String`, `healthRawValue: UInt`, `countsReps: Bool`, `showsZones: Bool`, `tracksDistance: Bool`, `id: String` (the name). `public enum ActivityCatalog` with `static let all: [ActivityType]`, `static let popular: [ActivityType]`, `static func type(named: String) -> ActivityType?`, `static func type(healthRawValue: UInt) -> ActivityType?`, `static func search(_ query: String) -> [ActivityType]`, `static func grouped() -> [(group: ActivityType.Group, types: [ActivityType])]`, and `static let other: ActivityType`.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/AppSurfacesTests/ActivityCatalogTests.swift`:

```swift
import Testing
@testable import AppSurfaces

struct ActivityCatalogTests {
    @Test func catalogHasEveryCurrentTypeOnce() {
        let all = ActivityCatalog.all
        #expect(all.count == 79)
        #expect(Set(all.map(\.name)).count == 79)
        #expect(Set(all.map(\.healthRawValue)).count == 79)
        // dance, danceInspiredTraining, mixedMetabolicCardioTraining, swimBikeRun, transition
        for excluded: UInt in [14, 15, 30, 82, 83] {
            #expect(ActivityCatalog.type(healthRawValue: excluded) == nil)
        }
        #expect(ActivityCatalog.type(healthRawValue: 3000)?.name == "Other")
    }

    @Test func lookupByNameIsExactThenCaseInsensitive() {
        #expect(ActivityCatalog.type(named: "Badminton")?.healthRawValue == 4)
        #expect(ActivityCatalog.type(named: "badminton")?.name == "Badminton")
        #expect(ActivityCatalog.type(named: "Nonsense") == nil)
        #expect(ActivityCatalog.type(named: "") == nil)
    }

    @Test func lookupByHealthValueRoundTripsEveryEntry() {
        for type in ActivityCatalog.all {
            #expect(ActivityCatalog.type(healthRawValue: type.healthRawValue) == type)
        }
    }

    @Test func popularIsTheOriginalSixInOrder() {
        #expect(ActivityCatalog.popular.map(\.name) == ["Walk", "Run", "Cycle", "Strength", "Yoga", "Other"])
        #expect(ActivityCatalog.other.name == "Other")
    }

    @Test func searchMatchesByNameAndKeepsCatalogOrder() {
        #expect(ActivityCatalog.search("bad").map(\.name) == ["Badminton"])
        #expect(ActivityCatalog.search("  Ski ").map(\.name) == ["Cross Country Skiing", "Downhill Skiing"])
        #expect(ActivityCatalog.search("").count == 79)
        #expect(ActivityCatalog.search("zzz").isEmpty)
    }

    @Test func groupedCoversEveryEntryOnceInCatalogOrder() {
        let grouped = ActivityCatalog.grouped()
        #expect(grouped.map(\.group) == ActivityType.Group.allCases)
        #expect(grouped.flatMap(\.types).count == 79)
        let sports = grouped.first { $0.group == .sports }?.types.map(\.name) ?? []
        #expect(sports.first == "Badminton")
        #expect(sports.contains("Pickleball") && sports.contains("Table Tennis"))
        for entry in grouped { #expect(entry.types == ActivityCatalog.all.filter { $0.group == entry.group }) }
    }

    @Test func flagsHoldForTheNamedEntries() {
        #expect(ActivityCatalog.all.filter(\.countsReps).map(\.name) == ["Strength", "Functional Strength"])
        let noZones = ActivityCatalog.all.filter { !$0.showsZones }.map(\.name)
        #expect(Set(noZones) == ["Yoga", "Pilates", "Tai Chi", "Flexibility", "Cooldown", "Preparation and Recovery", "Mind and Body"])
        let distance = ActivityCatalog.all.filter(\.tracksDistance).map(\.name)
        #expect(Set(distance) == ["Walk", "Run", "Cycle", "Hiking", "Wheelchair Walk Pace", "Wheelchair Run Pace", "Hand Cycling",
                                  "Swimming", "Rowing", "Paddle Sports", "Cross Country Skiing", "Downhill Skiing", "Snowboarding", "Skating"])
        #expect(ActivityCatalog.type(named: "Badminton")?.symbol == "figure.badminton")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities/LifeOSKit && swift test --filter ActivityCatalogTests 2>&1 | tail -5`
Expected: compile error, `cannot find 'ActivityCatalog' in scope`.

- [ ] **Step 3: Write the catalog**

Create `LifeOSKit/Sources/AppSurfaces/ActivityCatalog.swift`. The raw values are `HKWorkoutActivityType`'s from the iOS 26 SDK header; the symbols were checked against the macOS 26 symbol set on 2026-09-16 and the six that had no exact symbol use the nearest one.

```swift
import Foundation

/// One activity a person can record: what it is called, how it is drawn,
/// and how the recorder treats it. The name is both the display name and
/// the value stored on `WorkoutRecord.activityName` and on a session draft,
/// so it never changes once shipped.
public struct ActivityType: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case cardio = "Cardio"
        case strength = "Strength and Conditioning"
        case sports = "Racket and Ball Sports"
        case water = "Water"
        case outdoor = "Snow and Outdoor"
        case mindAndBody = "Mind and Body"
        case danceAndPlay = "Dance and Play"
        case other = "Other"
    }
    public let name: String
    public let group: Group
    /// An SF Symbol name.
    public let symbol: String
    /// `HKWorkoutActivityType.rawValue`. Kept as a number so this package
    /// stays free of HealthKit and keeps building for `swift test`.
    public let healthRawValue: UInt
    public let countsReps: Bool
    public let showsZones: Bool
    public let tracksDistance: Bool
    public var id: String { name }

    init(_ name: String, _ group: Group, _ symbol: String, _ healthRawValue: UInt,
         reps: Bool = false, zones: Bool = true, distance: Bool = false) {
        self.name = name; self.group = group; self.symbol = symbol; self.healthRawValue = healthRawValue
        countsReps = reps; showsZones = zones; tracksDistance = distance
    }
}

/// Every activity the Apple Watch Workout app offers, minus the three
/// HealthKit has deprecated and the two multisport containers.
public enum ActivityCatalog {
    public static let all: [ActivityType] = [
        // Cardio
        ActivityType("Walk", .cardio, "figure.walk", 52, distance: true),
        ActivityType("Run", .cardio, "figure.run", 37, distance: true),
        ActivityType("Cycle", .cardio, "figure.outdoor.cycle", 13, distance: true),
        ActivityType("Hiking", .cardio, "figure.hiking", 24, distance: true),
        ActivityType("Elliptical", .cardio, "figure.elliptical", 16),
        ActivityType("Rowing", .cardio, "figure.rower", 35, distance: true),
        ActivityType("Stair Climbing", .cardio, "figure.stair.stepper", 44),
        ActivityType("Stairs", .cardio, "figure.stairs", 68),
        ActivityType("Step Training", .cardio, "figure.step.training", 69),
        ActivityType("Jump Rope", .cardio, "figure.jumprope", 64),
        ActivityType("HIIT", .cardio, "figure.highintensity.intervaltraining", 63),
        ActivityType("Mixed Cardio", .cardio, "figure.mixed.cardio", 73),
        ActivityType("Cross Training", .cardio, "figure.cross.training", 11),
        ActivityType("Track and Field", .cardio, "figure.track.and.field", 49),
        ActivityType("Wheelchair Walk Pace", .cardio, "figure.roll", 70, distance: true),
        ActivityType("Wheelchair Run Pace", .cardio, "figure.roll.runningpace", 71, distance: true),
        ActivityType("Hand Cycling", .cardio, "figure.hand.cycling", 74, distance: true),
        // Strength and Conditioning
        ActivityType("Strength", .strength, "figure.strengthtraining.traditional", 50, reps: true),
        ActivityType("Functional Strength", .strength, "figure.strengthtraining.functional", 20, reps: true),
        ActivityType("Core Training", .strength, "figure.core.training", 59),
        ActivityType("Kickboxing", .strength, "figure.kickboxing", 65),
        ActivityType("Boxing", .strength, "figure.boxing", 8),
        ActivityType("Martial Arts", .strength, "figure.martial.arts", 28),
        ActivityType("Wrestling", .strength, "figure.wrestling", 56),
        ActivityType("Gymnastics", .strength, "figure.gymnastics", 22),
        ActivityType("Climbing", .strength, "figure.climbing", 9),
        ActivityType("Fencing", .strength, "figure.fencing", 18),
        ActivityType("Archery", .strength, "figure.archery", 2),
        // Racket and Ball Sports
        ActivityType("Badminton", .sports, "figure.badminton", 4),
        ActivityType("Tennis", .sports, "figure.tennis", 48),
        ActivityType("Table Tennis", .sports, "figure.table.tennis", 47),
        ActivityType("Pickleball", .sports, "figure.pickleball", 79),
        ActivityType("Squash", .sports, "figure.squash", 43),
        ActivityType("Racquetball", .sports, "figure.racquetball", 34),
        ActivityType("Basketball", .sports, "figure.basketball", 6),
        ActivityType("Soccer", .sports, "figure.soccer", 41),
        ActivityType("American Football", .sports, "figure.american.football", 1),
        ActivityType("Australian Football", .sports, "figure.australian.football", 3),
        ActivityType("Rugby", .sports, "figure.rugby", 36),
        ActivityType("Baseball", .sports, "figure.baseball", 5),
        ActivityType("Softball", .sports, "figure.softball", 42),
        ActivityType("Cricket", .sports, "figure.cricket", 10),
        ActivityType("Volleyball", .sports, "figure.volleyball", 51),
        ActivityType("Handball", .sports, "figure.handball", 23),
        ActivityType("Hockey", .sports, "figure.hockey", 25),
        ActivityType("Lacrosse", .sports, "figure.lacrosse", 27),
        ActivityType("Golf", .sports, "figure.golf", 21),
        ActivityType("Bowling", .sports, "figure.bowling", 7),
        ActivityType("Disc Sports", .sports, "figure.disc.sports", 75),
        ActivityType("Curling", .sports, "figure.curling", 12),
        // Water
        ActivityType("Swimming", .water, "figure.pool.swim", 46, distance: true),
        ActivityType("Water Fitness", .water, "figure.water.fitness", 53),
        ActivityType("Water Polo", .water, "figure.waterpolo", 54),
        ActivityType("Water Sports", .water, "figure.open.water.swim", 55),
        ActivityType("Surfing", .water, "figure.surfing", 45),
        ActivityType("Sailing", .water, "figure.sailing", 38),
        ActivityType("Paddle Sports", .water, "figure.outdoor.rowing", 31, distance: true),
        ActivityType("Underwater Diving", .water, "figure.open.water.swim", 84),
        // Snow and Outdoor
        ActivityType("Cross Country Skiing", .outdoor, "figure.skiing.crosscountry", 60, distance: true),
        ActivityType("Downhill Skiing", .outdoor, "figure.skiing.downhill", 61, distance: true),
        ActivityType("Snowboarding", .outdoor, "figure.snowboarding", 67, distance: true),
        ActivityType("Snow Sports", .outdoor, "figure.skiing.downhill", 40),
        ActivityType("Skating", .outdoor, "figure.skating", 39, distance: true),
        ActivityType("Fishing", .outdoor, "figure.fishing", 19),
        ActivityType("Hunting", .outdoor, "figure.hunting", 26),
        ActivityType("Equestrian Sports", .outdoor, "figure.equestrian.sports", 17),
        // Mind and Body
        ActivityType("Yoga", .mindAndBody, "figure.yoga", 57, zones: false),
        ActivityType("Pilates", .mindAndBody, "figure.pilates", 66, zones: false),
        ActivityType("Tai Chi", .mindAndBody, "figure.taichi", 72, zones: false),
        ActivityType("Barre", .mindAndBody, "figure.barre", 58),
        ActivityType("Flexibility", .mindAndBody, "figure.flexibility", 62, zones: false),
        ActivityType("Cooldown", .mindAndBody, "figure.cooldown", 80, zones: false),
        ActivityType("Preparation and Recovery", .mindAndBody, "figure.cooldown", 33, zones: false),
        ActivityType("Mind and Body", .mindAndBody, "figure.mind.and.body", 29, zones: false),
        // Dance and Play
        ActivityType("Cardio Dance", .danceAndPlay, "figure.dance", 77),
        ActivityType("Social Dance", .danceAndPlay, "figure.socialdance", 78),
        ActivityType("Play", .danceAndPlay, "figure.play", 32),
        ActivityType("Fitness Gaming", .danceAndPlay, "gamecontroller.fill", 76),
        // Other
        ActivityType("Other", .other, "figure.mixed.cardio", 3000),
    ]

    /// The six the app has always offered, in the order it offered them.
    public static let popular: [ActivityType] = ["Walk", "Run", "Cycle", "Strength", "Yoga", "Other"].compactMap { type(named: $0) }
    public static let other: ActivityType = all.last!

    private static let byName: [String: ActivityType] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    private static let byHealth: [UInt: ActivityType] = Dictionary(uniqueKeysWithValues: all.map { ($0.healthRawValue, $0) })

    /// Exact match first, so a stored name always resolves to itself; then
    /// case-insensitive, for anything typed.
    public static func type(named name: String) -> ActivityType? {
        if let exact = byName[name] { return exact }
        let folded = name.lowercased()
        guard !folded.isEmpty else { return nil }
        return all.first { $0.name.lowercased() == folded }
    }
    public static func type(healthRawValue value: UInt) -> ActivityType? { byHealth[value] }

    /// Name contains the trimmed query, case-insensitively, in catalog order.
    public static func search(_ query: String) -> [ActivityType] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(needle) }
    }
    /// Every group in declaration order, each holding its types in catalog order.
    public static func grouped() -> [(group: ActivityType.Group, types: [ActivityType])] {
        ActivityType.Group.allCases.map { group in (group, all.filter { $0.group == group }) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities/LifeOSKit && swift test --filter ActivityCatalogTests 2>&1 | tail -12`
Expected: `Test run with 7 tests in 1 suite passed`. If `catalogHasEveryCurrentTypeOnce` fails on the count, a line was dropped or duplicated; compare against the header list in the spec.

- [ ] **Step 5: Commit**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities
git add LifeOSKit/Sources/AppSurfaces/ActivityCatalog.swift LifeOSKit/Tests/AppSurfacesTests/ActivityCatalogTests.swift
git commit -m "feat(activity): the full activity catalog as shared data

Seventy nine activity types with name, group, symbol, HealthKit value and
the flags the recorder reads, in AppSurfaces so the phone, the Watch and
the widgets share one table."
```

---

### Task 2: The recorder adopts the catalog

**Files:**
- Create: `LIfeOS/Features/Activity/Model/ActivityType+Health.swift`
- Create: `LIfeOS/Features/Activity/Model/ActivityRecents.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift` (delete `RecordedActivity`, lines 9 to 33; `selection` at line 36; lines 165, 241, 260, 269, 274, 329, 409)
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorder+Watch.swift` (lines 28, 67, 75 to 77, 117, 129, 139, 145)
- Modify: `LIfeOS/Features/Activity/View/SessionRings.swift` (line 12, 29, 44, 89, 166, 190, 219, 220)
- Modify: `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` (lines 84, 102, 118, 136, 141, 154, 197 to 214; the picker is rebuilt in Task 3, this task only makes it compile)
- Modify: `LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift` (lines 35 to 42, 97)
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` (the `--strength` line)
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift` (lines 32, 81, 177)

**Interfaces:**
- Consumes: `ActivityCatalog`, `ActivityType` from Task 1.
- Produces: `extension ActivityType { var healthType: HKWorkoutActivityType }`; `extension ActivityCatalog { static let walk, run, cycle, strength, yoga: ActivityType }`; `struct ActivityRecents` with `init(defaults: UserDefaults)`, `var names: [String]`, `func types() -> [ActivityType]`, `mutating func record(_ type: ActivityType)`, `static let limit = 6`; `ActivityRecorder.selection: ActivityType`; `ActivityRecorder.recents: ActivityRecents`.

- [ ] **Step 1: Add the Health bridge and the named accessors**

Create `LIfeOS/Features/Activity/Model/ActivityType+Health.swift`:

```swift
import HealthKit
import AppSurfaces

extension ActivityType {
    /// The catalog stores the raw value so the package stays free of
    /// HealthKit. A value HealthKit rejects is a catalog bug the native
    /// check reports; at runtime the session still starts, as Other.
    var healthType: HKWorkoutActivityType { HKWorkoutActivityType(rawValue: healthRawValue) ?? .other }
}

extension ActivityCatalog {
    static let walk = type(named: "Walk")!
    static let run = type(named: "Run")!
    static let cycle = type(named: "Cycle")!
    static let strength = type(named: "Strength")!
    static let yoga = type(named: "Yoga")!
}
```

- [ ] **Step 2: Add the recents list**

Create `LIfeOS/Features/Activity/Model/ActivityRecents.swift`:

```swift
import Foundation
import AppSurfaces

/// The last activities this account started, most recent first, so the
/// picker leads with what the person actually does. Stored as names so a
/// renamed or removed catalog entry simply drops out of the list.
struct ActivityRecents {
    static let key = "activity.recents"
    static let limit = 6
    private let defaults: UserDefaults
    private(set) var names: [String]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        names = defaults.stringArray(forKey: Self.key) ?? []
    }
    /// Catalog entries for the stored names, skipping any that no longer exist.
    func types() -> [ActivityType] { names.compactMap { ActivityCatalog.type(named: $0) } }

    mutating func record(_ type: ActivityType) {
        names.removeAll { $0 == type.name }
        names.insert(type.name, at: 0)
        if names.count > Self.limit { names.removeLast(names.count - Self.limit) }
        defaults.set(names, forKey: Self.key)
    }
}
```

- [ ] **Step 3: Migrate `ActivityRecorder`**

In `LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift`:

Delete the whole `enum RecordedActivity { ... }` block (lines 9 to 33).

Replace `var selection: RecordedActivity = .walk` with:

```swift
    var selection: ActivityType = ActivityCatalog.walk
    /// The last six activities started on this account, for the picker.
    /// Same defaults as the draft, so the design preview's disposable suite
    /// keeps its own list.
    var recents: ActivityRecents
```

In `init(defaults:liveActivitiesEnabled:)` at line 128, add `recents = ActivityRecents(defaults: defaults)` directly after `self.defaults = defaults` (line 129), before `super.init()` at line 132.

Line 165, in the restore path: replace

```swift
        selection = RecordedActivity(rawValue: draft.timer.activity) ?? .other
```
with
```swift
        selection = ActivityCatalog.type(named: draft.timer.activity) ?? ActivityCatalog.other
```

Line 241, in `start`: replace `if selection == .strength {` with `if selection.countsReps {`. On the line before it (after `source = .phone`) add:

```swift
        recents.record(selection)
```

Line 260: `configuration.activityType = selection.healthType` stays as written; `healthType` is now the extension.

Lines 269 and 274: replace `activity: selection.rawValue` with `activity: selection.name` in both `ActivitySessionState(...)` calls.

Line 329: replace `if selection == .strength { row.sets = ...` with `if selection.countsReps { row.sets = ...`.

Line 409: `liveActivity.sync(readout, timer: timer, icon: selection.icon)` becomes `icon: selection.symbol`.

- [ ] **Step 4: Migrate the Watch mirror path**

In `LIfeOS/Features/Activity/ViewModel/ActivityRecorder+Watch.swift`:

Line 28: `configuration.activityType = selection.healthType` stays.

Line 67: replace

```swift
            selection = RecordedActivity.allCases.first { $0.healthType == mirrored.workoutConfiguration.activityType } ?? .other
```
with
```swift
            selection = ActivityCatalog.type(healthRawValue: mirrored.workoutConfiguration.activityType.rawValue) ?? ActivityCatalog.other
            recents.record(selection)
```

Line 75: `activity: selection.rawValue` becomes `activity: selection.name`.

Lines 76, 117, 129, 139, 145: every `selection == .strength` becomes `selection.countsReps`.

- [ ] **Step 5: Migrate `SessionRings`**

In `LIfeOS/Features/Activity/View/SessionRings.swift`, line 12: replace `let activity: RecordedActivity` with `let activity: ActivityType`. Line 29: `activity != .yoga && zonesAvailable` becomes `activity.showsZones && zonesAvailable`. Lines 44, 89, 166, 190: each `activity == .strength` becomes `activity.countsReps`. Lines 219 and 220 in the preview: `activity: .strength` becomes `activity: ActivityCatalog.strength` and `activity: .run` becomes `activity: ActivityCatalog.run`. The file already imports AppSurfaces.

- [ ] **Step 6: Make the remaining sites compile**

`LIfeOS/Features/Activity/View/BeginActivityScreen.swift`:
- Line 84 `model.selection.icon` becomes `model.selection.symbol`.
- Line 102 `Label(model.selection.rawValue, systemImage: model.selection.icon)` becomes `Label(model.selection.name, systemImage: model.selection.symbol)`.
- Line 136 `model.zonesAvailable, model.selection != .yoga` becomes `model.zonesAvailable, model.selection.showsZones`.
- Line 141 `model.selection == .strength` becomes `model.selection.countsReps`.
- Line 154 `[.walk, .run, .cycle].contains(model.selection)` becomes `model.selection.tracksDistance`.
- Lines 197 to 214, the picker grid: change `ForEach(RecordedActivity.allCases)` to `ForEach(ActivityCatalog.popular)`, `activity.icon` to `activity.symbol`, `activity.rawValue` to `activity.name`. Task 3 replaces this grid.

`LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift`, lines 35 to 42:

```swift
    /// The split decides what the recorder calls this session. A video is a
    /// strength session unless it plainly is not.
    static func activity(for split: String) -> ActivityType {
        switch split.lowercased() {
        case "cardio": ActivityCatalog.other
        case "mobility": ActivityCatalog.yoga
        default: ActivityCatalog.strength
        }
    }
```

Line 97: `model.selection == .strength, model.hasSession` becomes `model.selection.countsReps, model.hasSession`.

`LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`: `? .strength : .run` becomes `? ActivityCatalog.strength : ActivityCatalog.run`, and add `import AppSurfaces` under the existing imports; the file does not import it today.

`LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift`: line 32 `lifter.selection = .strength` becomes `lifter.selection = ActivityCatalog.strength`; line 81 `mirrored.selection == .strength` becomes `mirrored.selection.countsReps`; line 177 `stale.selection = .walk` becomes `stale.selection = ActivityCatalog.walk`.

- [ ] **Step 7: Build the app**

Run:
```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' build > /private/tmp/claude-501/-Users-shivvyas-LIfeOS/7f771eb3-97ab-437b-9be5-c6b86841eb22/scratchpad/t2-build.log 2>&1; grep -E "error:|BUILD (SUCCEEDED|FAILED)" /private/tmp/claude-501/-Users-shivvyas-LIfeOS/7f771eb3-97ab-437b-9be5-c6b86841eb22/scratchpad/t2-build.log | head
```
Expected: `BUILD SUCCEEDED`. Any remaining `RecordedActivity` reference is an error; grep the app for it: `grep -rn RecordedActivity LIfeOS` must print nothing.

- [ ] **Step 8: Commit**

```bash
git add -A LIfeOS
git commit -m "refactor(activity): recorder reads the catalog instead of a six case enum

Selection is an ActivityType; strength, zones and distance decisions come
from its flags. Stored names are unchanged, so drafts and records on disk
resolve as before. Starting a session records it in a per account recents
list."
```

---

### Task 3: Recents grid and the picker sheet

**Files:**
- Create: `LIfeOS/Features/Activity/View/ActivityPickerSheet.swift`
- Modify: `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` (the `activityPicker` computed property, and the `@State` block)

**Interfaces:**
- Consumes: `ActivityCatalog.grouped()`, `ActivityCatalog.search(_:)`, `ActivityRecorder.selection`, `ActivityRecorder.recents`.
- Produces: `struct ActivityPickerSheet: View` with `init(selection: Binding<ActivityType>, onChoose: @escaping (ActivityType) -> Void)`.

- [ ] **Step 1: Write the picker sheet**

Create `LIfeOS/Features/Activity/View/ActivityPickerSheet.swift`:

```swift
import SwiftUI
import DesignSystem
import AppSurfaces

/// Every activity, grouped, with a search field. A dialog on every device.
struct ActivityPickerSheet: View {
    @Binding var selection: ActivityType
    var onChoose: (ActivityType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var sections: [(group: ActivityType.Group, types: [ActivityType])] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ActivityCatalog.grouped() }
        let hits = Set(ActivityCatalog.search(trimmed).map(\.name))
        return ActivityCatalog.grouped()
            .map { (group: $0.group, types: $0.types.filter { hits.contains($0.name) }) }
            .filter { !$0.types.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(sections, id: \.group) { section in
                    Section(section.group.rawValue) {
                        ForEach(section.types) { type in
                            Button {
                                selection = type
                                onChoose(type)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: type.symbol).frame(width: 28)
                                    Text(type.name)
                                    Spacer()
                                    if type == selection { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
                                }
                                .frame(minHeight: 44)
                            }
                            .tint(.primary)
                            .accessibilityAddTraits(type == selection ? .isSelected : [])
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
            .navigationTitle("All activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(LifeOSTokens.accent)
    }
}
```

- [ ] **Step 2: Replace the picker grid**

In `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`, add to the state block:

```swift
    @State private var showAllActivities = false
```

Replace the whole `private var activityPicker: some View { ... }` with:

```swift
    /// The last six activities started, or the six the app always offered
    /// when the account has none yet, then a tile that opens everything.
    /// The current selection is always on the grid, even when it is not a
    /// recent, so the picked activity is never invisible.
    private var pickerTiles: [ActivityType] {
        var tiles = model.recents.types()
        if tiles.isEmpty { tiles = ActivityCatalog.popular }
        if !tiles.contains(model.selection) { tiles.append(model.selection) }
        return tiles
    }
    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your activity").font(LifeOSType.sectionTitle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                ForEach(pickerTiles) { activity in
                    pickerTile(activity.name, symbol: activity.symbol, selected: model.selection == activity) {
                        model.selection = activity
                    }
                }
                pickerTile("More", symbol: "ellipsis.circle", selected: false) { showAllActivities = true }
                    .accessibilityLabel("More activities")
            }
        }
        .sheet(isPresented: $showAllActivities) {
            ActivityPickerSheet(selection: $model.selection, onChoose: { _ in })
        }
    }
    private func pickerTile(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                Text(title).font(LifeOSType.rowTitle).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
            }
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .padding(16).frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? LifeOSTokens.accentSoft.resolve(scheme) : LifeOSTokens.cardSurface.resolve(scheme),
                        in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(model.busy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
```

Recording into recents happens when a session starts (Task 2), not when a tile is tapped, so browsing does not reorder the grid.

- [ ] **Step 3: Build the app**

Run the iOS build command from Global Constraints, logging to `t3-build.log`. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Activity/View/ActivityPickerSheet.swift LIfeOS/Features/Activity/View/BeginActivityScreen.swift
git commit -m "feat(activity): recents grid with a searchable picker for every activity

Begin Activity shows the last six activities started, or the original six
for a new account, and a More tile that opens the grouped, searchable
catalog."
```

---

### Task 4: Live Activity names and the Watch app

**Files:**
- Modify: `LIfeOS/App/Surfaces/WatchSessionBridge.swift:118-145`
- Modify: `AlmanacWatch/WatchWorkoutController.swift:13-14, 34, 61, 122`
- Modify: `AlmanacWatch/AlmanacWatchApp.swift:138-146`

**Interfaces:**
- Consumes: `ActivityCatalog.type(healthRawValue:)`, `ActivityCatalog.popular`, `ActivityCatalog.grouped()`, `ActivityType.countsReps`.
- Produces: `WatchWorkoutController.activity: ActivityType?`.

- [ ] **Step 1: The bridge reads the catalog**

In `LIfeOS/App/Surfaces/WatchSessionBridge.swift`, replace the two static functions and their comment (lines 123 to 145) with:

```swift
    /// The catalog's name and symbol for the type the wrist started, so the
    /// placeholder Live Activity matches the card the recorder shows later.
    static func name(for type: HKWorkoutActivityType) -> String {
        (ActivityCatalog.type(healthRawValue: type.rawValue) ?? ActivityCatalog.other).name
    }
    static func icon(for type: HKWorkoutActivityType) -> String {
        (ActivityCatalog.type(healthRawValue: type.rawValue) ?? ActivityCatalog.other).symbol
    }
```

Confirm the file imports `AppSurfaces` (it uses `WorkoutActivityAttributes`, so it does).

- [ ] **Step 2: The Watch controller reads the catalog**

In `AlmanacWatch/WatchWorkoutController.swift`:

Delete the `static let startable` declaration (lines 13 and 14).

After `private(set) var activityName = ""` add:

```swift
    /// The catalog entry for the running session, nil when idle.
    private(set) var activity: ActivityType?
```

Replace `var isStrength: Bool { session?.workoutConfiguration.activityType == .traditionalStrengthTraining }` with:

```swift
    var isStrength: Bool { activity?.countsReps == true }
```

Line 61, in `start(_ configuration:)`: replace

```swift
        activityName = Self.startable.first { $0.type == configuration.activityType }?.name ?? "Other"
```
with
```swift
        activity = ActivityCatalog.type(healthRawValue: configuration.activityType.rawValue) ?? ActivityCatalog.other
        activityName = activity?.name ?? "Other"
```

Line 122, in the recovery path, make the same replacement using `session.workoutConfiguration.activityType.rawValue`.

Lines 96 and 239, where `activityName = ""` is reset, add `activity = nil` beside it.

- [ ] **Step 3: The Watch start sheet lists every group**

In `AlmanacWatch/AlmanacWatchApp.swift`, replace the sheet body (lines 139 to 146):

```swift
        .sheet(isPresented: $isChoosingWorkout) {
            List {
                Section("Popular") {
                    ForEach(ActivityCatalog.popular) { type in startRow(type) }
                }
                ForEach(ActivityCatalog.grouped(), id: \.group) { section in
                    Section(section.group.rawValue) {
                        ForEach(section.types) { type in startRow(type) }
                    }
                }
            }
            .navigationTitle("Start workout")
        }
    }
    private func startRow(_ type: ActivityType) -> some View {
        Button {
            isChoosingWorkout = false
            onStartWorkout(HKWorkoutActivityType(rawValue: type.healthRawValue) ?? .other)
        } label: {
            Label(type.name, systemImage: type.symbol)
        }
```

The closing brace of `body` moves above `startRow`; keep `private func reading(...)` after it. The file already imports AppSurfaces.

- [ ] **Step 4: Build both apps**

Run the iOS build to `t4-ios.log` and the Watch build to `t4-watch.log`. Expected: both `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/App/Surfaces/WatchSessionBridge.swift AlmanacWatch/WatchWorkoutController.swift AlmanacWatch/AlmanacWatchApp.swift
git commit -m "feat(watch): start any catalog activity from the wrist

The Watch start sheet lists the popular six and then every group, the
controller takes reps from the catalog flag, and the placeholder Live
Activity names and draws the type from the same table."
```

---

### Task 5: Native checks for the catalog and recents

**Files:**
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift` (append inside the `do` block, before the final `} catch`)

**Interfaces:**
- Consumes: `ActivityRecents`, `ActivityType.healthType`, `ActivityRecorder.restore` path via the draft key.

- [ ] **Step 1: Add the checks**

Find the end of the `do { ... }` block in `ActivityRecorderChecks.run()` (the last `check(...)` before `} catch`). Insert before the `} catch` line:

```swift
            // Spec test 8: every catalog entry is a real HealthKit type with a symbol that draws.
            let badTypes = ActivityCatalog.all.filter { HKWorkoutActivityType(rawValue: $0.healthRawValue) == nil }
            let badSymbols = ActivityCatalog.all.filter { UIImage(systemName: $0.symbol) == nil }
            check(badTypes.isEmpty && badSymbols.isEmpty,
                  "Every catalog entry maps to HealthKit and an SF Symbol" + (badTypes + badSymbols).map { " · \($0.name)" }.joined())
            // Spec test 9: recents are most recent first, deduplicated, capped at six.
            let recentSuite = suite + ".recents"
            let recentDefaults = UserDefaults(suiteName: recentSuite)!
            defer { recentDefaults.removePersistentDomain(forName: recentSuite) }
            var recents = ActivityRecents(defaults: recentDefaults)
            recents.record(ActivityCatalog.type(named: "Badminton")!)
            recents.record(ActivityCatalog.run)
            check(recents.names == ["Run", "Badminton"], "Recents lead with the latest start")
            recents.record(ActivityCatalog.run)
            check(recents.names == ["Run", "Badminton"], "Starting an activity again does not duplicate it")
            for name in ["Tennis", "Squash", "Yoga", "Golf", "Pilates"] { recents.record(ActivityCatalog.type(named: name)!) }
            check(recents.names.count == ActivityRecents.limit && !recents.names.contains("Badminton"),
                  "The seventh distinct start drops the oldest recent")
            check(ActivityRecents(defaults: recentDefaults).names == recents.names, "Recents persist across instances")
            // Spec test 10: a restored draft resolves its name through the catalog.
            let restoreSuite = suite + ".restore"
            let restoreDefaults = UserDefaults(suiteName: restoreSuite)!
            defer { restoreDefaults.removePersistentDomain(forName: restoreSuite) }
            let pilates = ActivityRecorder(defaults: restoreDefaults, liveActivitiesEnabled: false)
            pilates.attach(context); pilates.saveToHealth = false
            pilates.selection = ActivityCatalog.type(named: "Pilates")!
            await pilates.start()
            pilates.deactivate()
            let restored = ActivityRecorder(defaults: restoreDefaults, liveActivitiesEnabled: false)
            restored.attach(context)
            check(restored.selection.name == "Pilates" && !restored.selection.countsReps && !restored.selection.showsZones,
                  "A restored Pilates draft selects Pilates with reps and zones off")
            await restored.discard()
            let nonsenseSuite = suite + ".nonsense"
            let nonsenseDefaults = UserDefaults(suiteName: nonsenseSuite)!
            defer { nonsenseDefaults.removePersistentDomain(forName: nonsenseSuite) }
            let draft = ActivityRecorder.Draft(timer: ActivitySessionState(activity: "Nonsense"), healthSaved: false, recordsHealth: false)
            nonsenseDefaults.set(try JSONEncoder().encode(draft), forKey: ActivityRecorder.draftKey)
            let odd = ActivityRecorder(defaults: nonsenseDefaults, liveActivitiesEnabled: false)
            odd.attach(context)
            check(odd.selection.name == "Other", "A draft with an unknown activity name selects Other")
            await odd.discard()
```

Add `import UIKit` and `import HealthKit` at the top of the file; today it imports Foundation, SwiftData, Persistence, Integrations and AppSurfaces only. `ActivityRecorder.Draft` (line 107) and `draftKey` (line 91) are `private`: drop `private` from both so they are internal to the module. `Draft`'s memberwise init takes `timer`, `healthSaved` and then optionals with nil defaults, which is why the call above passes `healthSaved: false`. `discard()` (line 354) abandons a session without saving and `deactivate()` (line 369) detaches the recorder; both exist with those names.

- [ ] **Step 2: Build and run the checks in the simulator**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities
S=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/7f771eb3-97ab-437b-9be5-c6b86841eb22/scratchpad
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' build > $S/t5-build.log 2>&1; grep -E "error:|BUILD" $S/t5-build.log | head -3
APP=$(dirname "$(grep -l ipad-activities ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist)")/Build/Products/Debug-iphonesimulator/LIfeOS.app
SIM=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4; BID=com.shivvyas.lifeos
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl install $SIM "$APP"
xcrun simctl launch $SIM $BID --design-preview --page=checks >/dev/null; perl -e 'select(undef,undef,undef,25)'
cat "$(xcrun simctl get_app_container $SIM $BID data)/Documents/recorder-checks.txt"
```

Expected: every line starts with `PASS`, including the six new names. A `FAIL` on the symbol check prints the offending names after the message; fix the symbol in the catalog and rerun.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Activity/ViewModel/ActivityRecorderChecks.swift LIfeOS/Features/Activity/ViewModel/ActivityRecorder.swift
git commit -m "test(activity): native checks for the catalog, recents and draft restore"
```

---

### Task 6: Begin Activity fills an iPad

**Files:**
- Modify: `LIfeOS/App/RootView.swift:139-143`
- Modify: `LIfeOS/Features/Activity/View/BeginActivityScreen.swift` (the `body` scroll content)

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Present as a full-screen cover on regular width**

In `LIfeOS/App/RootView.swift`, replace lines 139 to 143:

```swift
        .sheet(isPresented: $showActivity, onDismiss: {
            if quickLogAfterActivity { quickLogAfterActivity = false; showQuickLog = true }
        }) {
            BeginActivityScreen(model: recorder, onQuickLog: { quickLogAfterActivity = true }, library: library)
        }
```
with
```swift
        // A sheet on an iPad is a centered card, and the live session and
        // the video it pushes would be stuck inside it. Regular width gets
        // the cover Settings and the Coach already use.
        .sheet(isPresented: Binding(get: { showActivity && sizeClass != .regular }, set: { showActivity = $0 }),
               onDismiss: afterActivity) { activityScreen }
        .fullScreenCover(isPresented: Binding(get: { showActivity && sizeClass == .regular }, set: { showActivity = $0 }),
                         onDismiss: afterActivity) { activityScreen }
```

Add these two members near `showActivity`:

```swift
    private var activityScreen: some View {
        BeginActivityScreen(model: recorder, onQuickLog: { quickLogAfterActivity = true }, library: library)
    }
    private func afterActivity() {
        if quickLogAfterActivity { quickLogAfterActivity = false; showQuickLog = true }
    }
```

- [ ] **Step 2: Two columns at 900 points**

In `LIfeOS/Features/Activity/View/BeginActivityScreen.swift`, add to the environment block:

```swift
    @Environment(\.horizontalSizeClass) private var sizeClass
```

Replace the `ScrollView { VStack(alignment: .leading, spacing: 22) { ... } .frame(maxWidth: 620)... }` content so the scroll view reads its width and picks a layout. The existing `VStack` body becomes two computed properties, `leading` and `trailing`, and the scroll view lays them out:

```swift
            ScrollView {
                GeometryReader { _ in EmptyView() }.frame(height: 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                if sizeClass == .regular, width >= 900 {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 22) { leading }.frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 22) { trailing }.frame(maxWidth: 420, alignment: .topLeading)
                    }
                    .padding(22).padding(.bottom, 20)
                } else {
                    VStack(alignment: .leading, spacing: 22) {
                        leading
                        trailing
                    }
                    .frame(maxWidth: 620).frame(maxWidth: .infinity).padding(22).padding(.bottom, 20)
                }
            }
```

with `@State private var width: CGFloat = 0` in the state block, and:

```swift
    /// The session itself: hero or timer, the tiles, the picker.
    @ViewBuilder private var leading: some View {
        if model.hasSession, let readout = model.readout {
            liveHero(readout)
            liveTiles(readout)
        } else {
            AccountPageHeading(title: model.saved ? "Time well spent." : "Make time to move.",
                detail: model.saved ? (model.healthSaved ? "Saved to Almanac and Apple Health." : "Saved to your Almanac account on this device.") : "One activity. Your own pace.")
            timerCard
            if !model.saved {
                if let library { followVideoLink(library) }
                activityPicker
            }
        }
        if let notice = model.notice { Text(notice).font(LifeOSType.caption).foregroundStyle(.secondary) }
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(LifeOSType.secondary).foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
        }
    }
    /// Controls, connections and the quick log: beside the session on a
    /// wide screen, under it otherwise.
    @ViewBuilder private var trailing: some View {
        ActivityControls(model: model, onDone: { dismiss() })
        if !model.saved { connections }
        if !model.hasSession && !model.saved {
            Button { dismiss(); onQuickLog() } label: {
                Label("Log steps, weight or a reflection", systemImage: "square.and.pencil")
                    .font(LifeOSType.label).frame(maxWidth: .infinity, minHeight: 48)
            }.tint(LifeOSTokens.accent)
        }
    }
```

The live gradient in `.background(alignment: .top)` already spans the scroll view's width; leave it.

- [ ] **Step 3: Build**

Run the iOS build to `t6-build.log`. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/App/RootView.swift LIfeOS/Features/Activity/View/BeginActivityScreen.swift
git commit -m "feat(activity): Begin Activity fills an iPad

Regular width presents it as a full screen cover instead of a centered
card, and at 900 points the session sits beside its controls in two
columns."
```

---

### Task 7: The video screen fills an iPad

**Files:**
- Modify: `LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift:44-70` and the `portrait` property (lines 72 to 114)

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Landscape by aspect**

Replace `@Environment(\.verticalSizeClass) private var verticalSizeClass` with:

```swift
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The screen's own size. Landscape is wider than tall, which an iPad
    /// reports where the compact vertical size class never would.
    @State private var screen = CGSize.zero
```

Replace `private var isLandscape: Bool { verticalSizeClass == .compact }` with:

```swift
    private var isLandscape: Bool { screen.width > screen.height }
    private var isWide: Bool { sizeClass == .regular && screen.width >= 900 }
```

In `body`, wrap the `Group` so the size is read at the root. Replace

```swift
        Group {
            if isFullScreen {
                fullScreen
            } else {
                portrait
            }
        }
```
with
```swift
        Group {
            if isFullScreen {
                fullScreen
            } else {
                portrait
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
```

The modifier reads the size of the screen's own frame, which is the full pane in every presentation this screen appears in.

- [ ] **Step 2: Wide portrait layout**

Replace the `private var portrait: some View { ... }` property with:

```swift
    private var portrait: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 28) {
                        playerCard.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 18) { portraitDetails }.frame(width: 360)
                    }
                    .padding(20).padding(.bottom, 24)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        playerCard
                        portraitDetails
                    }
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .padding(20).padding(.bottom, 24)
                }
            }
        }
    }

    /// The player with its rings and the full-screen button.
    private var playerCard: some View {
        player
            .aspectRatio(VideoWorkoutLayout.playerAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                if model.hasSession, let readout = model.readout {
                    DraggableHUD(placement: "compact",
                                 avoiding: { VideoWorkoutLayout.controlStrip(in: $0) }) {
                        rings(readout, repControls: false)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                fullScreenButton(entering: true).padding(VideoWorkoutLayout.overlayInset)
            }
    }

    /// Everything under, or beside, the player.
    @ViewBuilder private var portraitDetails: some View {
        openInYouTube
        details
        if model.hasSession || model.saved {
            if model.readout != nil {
                elapsedLine
                if model.selection.countsReps, model.hasSession { repControlsRow }
            }
            ActivityControls(model: model, onDone: { dismiss() })
        } else {
            startButton
        }
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
        }
    }
```

The 60 percent split from the spec is what `maxWidth: .infinity` beside a fixed 360 point column produces on a 1024 to 1366 point pane; no ratio arithmetic is needed.

- [ ] **Step 3: Build**

Run the iOS build to `t7-build.log`. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Workouts/View/VideoWorkoutScreen.swift
git commit -m "feat(workouts): the video fills an iPad in both orientations

Landscape is decided by aspect, so turning an iPad enters the full screen
player the way a phone does, and a wide portrait pane puts the details
beside the player."
```

---

### Task 8: iPad verification, screenshots and docs

**Files:**
- Create: `docs/design/ipad/begin-activity.png`, `docs/design/ipad/live-session.png`, `docs/design/ipad/video-landscape.png`, `docs/design/ipad/activity-picker.png`
- Modify: `docs/design/widgets-watch/implementation.md` (append one paragraph)

**Interfaces:**
- Consumes: the built app from Task 7.

- [ ] **Step 1: Build for the iPad and run the design preview pages**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities
S=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/7f771eb3-97ab-437b-9be5-c6b86841eb22/scratchpad
IPAD=9CFEE6A6-F8A5-4A50-A8ED-F1C15C322C8E; BID=com.shivvyas.lifeos
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination "id=$IPAD" build > $S/t8-build.log 2>&1; grep -E "error:|BUILD" $S/t8-build.log | head -3
APP=$(dirname "$(grep -l ipad-activities ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist)")/Build/Products/Debug-iphonesimulator/LIfeOS.app
xcrun simctl boot $IPAD 2>/dev/null; open -a Simulator --args -CurrentDeviceUDID $IPAD
xcrun simctl install $IPAD "$APP"
mkdir -p docs/design/ipad
# Begin Activity, idle, landscape
xcrun simctl launch $IPAD $BID --design-preview --page=activity >/dev/null; perl -e 'select(undef,undef,undef,6)'
xcrun simctl io $IPAD screenshot docs/design/ipad/begin-activity.png; xcrun simctl terminate $IPAD $BID
# Live session with readings
xcrun simctl launch $IPAD $BID --design-preview --page=activity --live --strength >/dev/null; perl -e 'select(undef,undef,undef,8)'
xcrun simctl io $IPAD screenshot docs/design/ipad/live-session.png; xcrun simctl terminate $IPAD $BID
# Video player in landscape
xcrun simctl launch $IPAD $BID --design-preview --page=player >/dev/null; perl -e 'select(undef,undef,undef,8)'
xcrun simctl io $IPAD screenshot docs/design/ipad/video-landscape.png; xcrun simctl terminate $IPAD $BID
```

The iPad simulator boots in portrait. Rotate it to landscape once before the captures with `osascript -e 'tell application "System Events" to keystroke "right arrow" using command down'` after bringing the Simulator frontmost (`osascript -e 'tell application "System Events" to set frontmost of process "Simulator" to true'`), then wait two seconds. If `--page=player` does not exist in `HealthActivityDesignPreview`, read its `page ==` branches and use the one that mounts `VideoWorkoutScreen`; if none does, capture the video from the running app instead by opening Begin Activity, Follow a video, and the first row, using the tap recipe in the simulator memory note.

- [ ] **Step 2: Capture the picker**

The picker needs a tap on the More tile. Bring the Simulator frontmost, read the AXGroup geometry as the simulator memory note describes, map the More tile's position from `begin-activity.png`, click it with `cliclick`, wait two seconds, then:

```bash
xcrun simctl io $IPAD screenshot docs/design/ipad/activity-picker.png
```

If two clicks in a row leave the screenshot unchanged, stop and report it rather than looping; the sheet is also exercised by the phone build and the catalog tests.

- [ ] **Step 3: Read every screenshot**

Open each PNG with the Read tool and confirm: Begin Activity fills the iPad with two columns; the live session shows the hero on the left and controls on the right; the video in landscape fills the screen with the HUD and no navigation bar; the picker lists Racket and Ball Sports with Badminton. If a capture shows the old single column, check `width >= 900` fired: the design preview may wrap the screen in a narrower container, in which case note it and capture from the real app flow instead.

- [ ] **Step 4: Run the phone and Watch builds and the package tests one last time**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/ipad-activities/LifeOSKit && swift test 2>&1 | tail -3
cd .. && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' build > $S/t8-ios.log 2>&1; grep -E "error:|BUILD" $S/t8-ios.log | head -3
xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' build > $S/t8-watch.log 2>&1; grep -E "error:|BUILD" $S/t8-watch.log | head -3
```

Expected: all package suites pass, both builds succeed.

- [ ] **Step 5: Document**

Append to `docs/design/widgets-watch/implementation.md`:

```markdown

iPad and the activity catalog (2026-09-16): Begin Activity presents as a full screen cover on regular width, so the live session and the workout video are no longer confined to a centered card on an iPad; the video screen decides landscape by aspect, so rotating an iPad enters the full screen player; and both live screens use two columns at 900 points and up. `ActivityCatalog` in AppSurfaces holds all 79 current Apple workout types with name, group, symbol, HealthKit value and the reps, zones and distance flags; the recorder, the Watch controller and the Live Activity read it, the phone keeps a per account recents list, and Begin Activity opens a searchable grouped picker from a More tile. Stored activity names are unchanged. Verification: seven `ActivityCatalogTests`, six new native checks in `ActivityRecorderChecks`, iPad screenshots in `docs/design/ipad/`, and the phone, Watch and extension builds.
```

- [ ] **Step 6: Commit**

```bash
git add docs/design/ipad docs/design/widgets-watch/implementation.md
git commit -m "docs(activity): iPad screenshots and the catalog note"
```

---

## Self-review

**Spec coverage.** Presentation (Task 6 step 1), landscape detection (Task 7 step 1), wide layouts for both screens (Tasks 6 and 7), catalog data and lookups (Task 1), recents (Task 2), `RecordedActivity` removal with every listed call site (Task 2), picker (Task 3), bridge and Watch (Task 4), package tests 1 to 7 (Task 1), native checks 8 to 10 (Task 5), iPad screenshots and builds (Task 8), doc paragraph (Task 8). "Other sheets stay sheets" needs no task. The spec's `tracksDistance` list is reproduced in the catalog and asserted in the flag test.

**Placeholders.** None; every code step carries its code. Task 5 names two things the implementer must read rather than assume (`Draft`'s init and the abandon method), with the search terms to find them.

**Type consistency.** `ActivityType.symbol` is used everywhere the old `icon` was; `name` where `rawValue` was; `countsReps`, `showsZones`, `tracksDistance` are the only flags; `ActivityCatalog.other` is a stored property, `popular` an array, `grouped()` returns labeled tuples `(group:, types:)` and the picker and Watch iterate it with `id: \.group`; `ActivityRecents.record(_:)` and `types()` match between Tasks 2, 3 and 5; `ActivityRecorder.recents` is read by the picker in Task 3.
