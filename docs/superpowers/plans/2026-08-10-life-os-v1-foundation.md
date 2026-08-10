# Life OS V1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running Life OS app with the complete design system, local data layer, and all five V1 screens rendering from seeded data — everything except the HealthKit, Whoop, and Supabase integrations.

**Architecture:** A local Swift package `LifeOSKit` provides compile-time module boundaries (`DesignSystem`, `Persistence`). All display logic that can be tested without a simulator lives in the package as pure functions and is developed test-first. SwiftUI views are verified by previews and a build, not by unit tests — testing view bodies is low-value ceremony. The app target contains only screens and wiring.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SwiftData, Swift Testing (`import Testing`), SwiftPM local package.

**Source spec:** `docs/superpowers/specs/2026-08-10-life-os-design.md`

## Global Constraints

- **Swift 6 language mode**, strict concurrency. The project currently reads `SWIFT_VERSION = 5.0` and must be migrated in Task 1.
- **iOS 26.0 minimum deployment target.** Required by the V2 `FoundationModels` dependency; set now so it is never a migration.
- **Bundle ID stays `shivvyas.LIfeOS`.** The capital-`I` project name is cosmetic and is deliberately not being changed.
- **Every metric field on `DailyMetrics` is optional.** A missing value and a zero must never be representable as the same thing. This is a health app; a false zero is worse than a blank.
- **Orange is the only accent colour** and never varies by module. It means *today* and it means *act*, nothing else.
- **Never render a numeral without its unit label.**
- **No HealthKit, Whoop, or Supabase code in this plan.** Those are Plans 2 and 3. Do not add the dependencies.
- **`DesignSystem` depends on nothing.** `Persistence` depends on nothing. If a task seems to require otherwise, the task is wrong — stop and flag it.
- Tests run from the terminal: `swift test --package-path LifeOSKit`. No simulator required for any test in this plan.

---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `LifeOSKit/Package.swift` | Package manifest, two library targets, two test targets |
| `LifeOSKit/Sources/DesignSystem/Tokens.swift` | `ModuleHue`, accent, canvas colours, light + dark variants |
| `LifeOSKit/Sources/DesignSystem/GradientCanvas.swift` | The one gradient primitive |
| `LifeOSKit/Sources/DesignSystem/MonthGridLayout.swift` | Pure layout maths for the dot grid (tested) |
| `LifeOSKit/Sources/DesignSystem/DotGrid.swift` | The dot grid view |
| `LifeOSKit/Sources/DesignSystem/GlassCard.swift` | Two card treatments by zone |
| `LifeOSKit/Sources/DesignSystem/HeroNumeral.swift` | The 96pt numeral + unit label |
| `LifeOSKit/Sources/DesignSystem/StatTile.swift` | Small metric tile |
| `LifeOSKit/Sources/DesignSystem/WeekStrip.swift` | Seven-day header strip |
| `LifeOSKit/Sources/Persistence/DailyMetrics.swift` | The daily spine model |
| `LifeOSKit/Sources/Persistence/UserGoals.swift` | Daily targets model |
| `LifeOSKit/Sources/Persistence/SourceRecords.swift` | `WorkoutRecord`, `SleepRecord` |
| `LifeOSKit/Sources/Persistence/GoalEvaluation.swift` | `DayReading`, `GoalTargets`, `DayStatus`, `evaluate` (tested) |
| `LifeOSKit/Sources/Persistence/Streak.swift` | Streak arithmetic (tested) |
| `LifeOSKit/Sources/Persistence/MetricsStore.swift` | Upsert + fetch against a `ModelContext` (tested) |
| `LifeOSKit/Sources/Persistence/LifeOSContainer.swift` | Schema + container factory, incl. in-memory for tests |
| `LifeOSKit/Sources/Persistence/SeedData.swift` | 60 days of plausible data for previews and first run |
| `LIfeOS/RootView.swift` | Tab bar, FAB, screen hosting |
| `LIfeOS/Screens/*.swift` | Five screens + quick-log sheet |
| `Config/Secrets.example.xcconfig` | Committed template (values arrive in Plan 3) |

**Modified:** `LIfeOS.xcodeproj/project.pbxproj` (Swift 6, iOS 26, package reference), `LIfeOS/LIfeOSApp.swift` (container injection), `.gitignore`.

**Deleted:** `LIfeOS/ContentView.swift`.

---

### Task 1: Project migration and package skeleton

Sets the language mode, deployment target, and creates `LifeOSKit` with one trivially-passing test proving the toolchain works end to end.

**Files:**
- Create: `LifeOSKit/Package.swift`
- Create: `LifeOSKit/Sources/DesignSystem/Tokens.swift`
- Create: `LifeOSKit/Sources/Persistence/GoalEvaluation.swift`
- Create: `LifeOSKit/Tests/PersistenceTests/GoalEvaluationTests.swift`
- Create: `.gitignore`, `Config/Secrets.example.xcconfig`
- Modify: `LIfeOS.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: package `LifeOSKit` with library products `DesignSystem` and `Persistence`, both importable from the app target.

- [ ] **Step 1: Create the package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "Persistence"),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
```

`DesignSystemTests` is deliberately **not** declared yet. SwiftPM fails if a
declared target's directory is missing, and declaring it now would force an
assertion-free placeholder test into the suite. Task 2 adds the target and its
first real test together.

`macOS` is declared **only so `swift test` runs from the terminal without a simulator.** The app itself ships iOS-only. Plans 2 and 3 will guard HealthKit code with `#if canImport(HealthKit)` to preserve this.

- [ ] **Step 2: Create the DesignSystem source directory**

SwiftPM fails with "Source files for target X should be located under…" if a
declared target's directory does not exist. Create this *before* running any
test, or the failure in Step 4 will be the wrong failure.

`LifeOSKit/Sources/DesignSystem/Tokens.swift`:

```swift
import SwiftUI

/// Namespace for Life OS design tokens. Populated in Task 2.
public enum LifeOSTokens {}
```

- [ ] **Step 3: Write the failing test**

`LifeOSKit/Tests/PersistenceTests/GoalEvaluationTests.swift`:

```swift
import Testing
@testable import Persistence

@Suite struct GoalEvaluationTests {
    @Test func defaultTargetsMatchTheSpec() {
        let targets = GoalTargets.default
        #expect(targets.steps == 8000)
        #expect(targets.sleepMinutes == 420)
        #expect(targets.exerciseMinutes == 30)
        #expect(targets.waterML == 2500)
        #expect(targets.requiredCount == 3)
    }
}
```

- [ ] **Step 4: Run it and confirm it fails**

Run: `swift test --package-path LifeOSKit --filter GoalEvaluationTests`
Expected: compile failure — `cannot find 'GoalTargets' in scope`.

- [ ] **Step 5: Write the minimal implementation**

`LifeOSKit/Sources/Persistence/GoalEvaluation.swift`:

```swift
import Foundation

public struct GoalTargets: Sendable, Equatable {
    public var steps: Int
    public var sleepMinutes: Int
    public var exerciseMinutes: Int
    public var waterML: Double
    public var requiredCount: Int

    public init(steps: Int, sleepMinutes: Int, exerciseMinutes: Int, waterML: Double, requiredCount: Int) {
        self.steps = steps
        self.sleepMinutes = sleepMinutes
        self.exerciseMinutes = exerciseMinutes
        self.waterML = waterML
        self.requiredCount = requiredCount
    }

    public static let `default` = GoalTargets(
        steps: 8000,
        sleepMinutes: 420,
        exerciseMinutes: 30,
        waterML: 2500,
        requiredCount: 3
    )
}
```

- [ ] **Step 6: Run the test and confirm it passes**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, 1 test.

- [ ] **Step 7: Migrate the Xcode project**

In Xcode, select the `LIfeOS` project → target `LIfeOS` → Build Settings, and set:
- `Swift Language Version` → **6**
- `Minimum Deployments` → **iOS 26.0**

Then File → Add Package Dependencies… → **Add Local…** → select the `LifeOSKit` folder → add both `DesignSystem` and `Persistence` to the `LIfeOS` target.

Verify from the terminal:

```bash
grep -E "SWIFT_VERSION|IPHONEOS_DEPLOYMENT_TARGET" LIfeOS.xcodeproj/project.pbxproj | sort -u
```

Expected: `SWIFT_VERSION = 6.0;` and `IPHONEOS_DEPLOYMENT_TARGET = 26.0;` only. If `5.0` still appears, the setting was applied to one configuration and not the other — fix Debug *and* Release.

- [ ] **Step 8: Add gitignore and secrets template**

`.gitignore`:

```
.DS_Store
xcuserdata/
*.xcuserstate
.build/
DerivedData/
Config/Secrets.xcconfig
```

`Config/Secrets.example.xcconfig`:

```
// Copy to Config/Secrets.xcconfig and fill in. That file is gitignored.
// None of these are true secrets — the Supabase anon key is designed to ship
// in clients and is safe because Row Level Security gates every row.
// Real secrets (service_role, Whoop client secret, Anthropic key) live only
// in Supabase Edge Function environments. Never add them here.
SUPABASE_URL      =
SUPABASE_ANON_KEY =
WHOOP_CLIENT_ID   =
```

- [ ] **Step 9: Confirm the app still builds, then commit**

```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If the simulator name is unavailable, run `xcrun simctl list devices available | grep iPhone` and substitute one.

```bash
git add -A
git commit -m "chore: migrate to Swift 6 / iOS 26 and add LifeOSKit package"
```

---

### Task 2: Design tokens

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/Tokens.swift`
- Modify: `LifeOSKit/Package.swift` (declare the `DesignSystemTests` target)
- Create: `LifeOSKit/Tests/DesignSystemTests/TokensTests.swift`

**Interfaces:**
- Produces: `ModuleHue` (enum, `CaseIterable`, `Sendable`) with `.top`/`.bottom`/`.darkTop`/`.darkBottom`; `AdaptiveColor`; `LifeOSTokens.accent`, `.canvas`, `.cardSurface`, `.primaryText`, `.secondaryText`, `.dotMissed`, `.dotFuture`, `.dotOutline`.

- [ ] **Step 1: Declare the test target and write the failing test**

Add to the `targets:` array in `LifeOSKit/Package.swift`:

```swift
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
```

`LifeOSKit/Tests/DesignSystemTests/TokensTests.swift`:

```swift
import Testing
@testable import DesignSystem

@Suite struct TokensTests {
    @Test func everyModuleHasADistinctHue() {
        let names = Set(ModuleHue.allCases.map(\.rawValue))
        #expect(names.count == ModuleHue.allCases.count)
        #expect(names == ["body", "activity", "recovery", "nutrition", "money", "habits"])
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --package-path LifeOSKit --filter TokensTests`
Expected: `cannot find 'ModuleHue' in scope`.

- [ ] **Step 3: Implement the tokens**

```swift
import SwiftUI

/// A module's identity colour. Each screen owns exactly one.
/// Nutrition, money and habits are declared now but unused until later slices —
/// declaring them proves the gradient primitive generalises.
public enum ModuleHue: String, CaseIterable, Sendable {
    case body, activity, recovery, nutrition, money, habits

    /// Saturated colour at the top of the canvas.
    public var top: Color {
        switch self {
        case .body:      Color(red: 0.06, green: 0.55, blue: 0.53)
        case .activity:  Color(red: 0.92, green: 0.68, blue: 0.16)
        case .recovery:  Color(red: 0.23, green: 0.51, blue: 0.93)
        case .nutrition: Color(red: 0.49, green: 0.36, blue: 0.92)
        case .money:     Color(red: 0.18, green: 0.62, blue: 0.36)
        case .habits:    Color(red: 0.94, green: 0.42, blue: 0.20)
        }
    }

    /// Near-white bottom of the canvas in light mode.
    public var bottom: Color { Color(white: 0.98) }

    /// Deep top / near-black bottom for dark mode. Defined now because
    /// retrofitting a gradient system to dark mode later is miserable.
    public var darkTop: Color {
        switch self {
        case .body:      Color(red: 0.02, green: 0.22, blue: 0.21)
        case .activity:  Color(red: 0.35, green: 0.25, blue: 0.04)
        case .recovery:  Color(red: 0.07, green: 0.17, blue: 0.35)
        case .nutrition: Color(red: 0.18, green: 0.13, blue: 0.36)
        case .money:     Color(red: 0.05, green: 0.23, blue: 0.13)
        case .habits:    Color(red: 0.36, green: 0.15, blue: 0.06)
        }
    }

    public var darkBottom: Color { Color(white: 0.06) }
}

/// A light/dark colour pair, resolved explicitly by the consuming view.
///
/// UIKit's dynamic colours (`Color(.systemGroupedBackground)`) would be simpler
/// but are iOS-only, and this package also builds for macOS so that tests run
/// from the terminal without a simulator. Explicit resolution is the price of
/// keeping `swift test` fast.
public struct AdaptiveColor: Sendable {
    public let light: Color
    public let dark: Color

    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    public func resolve(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}

public enum LifeOSTokens {
    /// The single accent. Means "today" and "act". Never varies by module,
    /// and is identical in both schemes so it reads the same everywhere.
    public static let accent = Color(red: 0.94, green: 0.34, blue: 0.18)

    /// Warm off-white canvas for the neutral hub.
    public static let canvas = AdaptiveColor(
        light: Color(red: 0.949, green: 0.945, blue: 0.933),
        dark: Color(white: 0.07)
    )

    public static let cardSurface = AdaptiveColor(
        light: .white,
        dark: Color(white: 0.13)
    )

    public static let primaryText = AdaptiveColor(
        light: Color(white: 0.08),
        dark: Color(white: 0.95)
    )

    public static let secondaryText = AdaptiveColor(
        light: Color(white: 0.45),
        dark: Color(white: 0.62)
    )

    /// Dot grid fills for days that were logged but missed, and days not yet reached.
    public static let dotMissed = AdaptiveColor(light: Color(white: 0.86), dark: Color(white: 0.28))
    public static let dotFuture = AdaptiveColor(light: Color(white: 0.93), dark: Color(white: 0.18))
    public static let dotOutline = AdaptiveColor(light: Color(white: 0.85), dark: Color(white: 0.30))
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `swift test --package-path LifeOSKit --filter TokensTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit
git commit -m "feat(design): add module hues and core tokens"
```

---

### Task 3: Gradient canvas

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/GradientCanvas.swift`

**Interfaces:**
- Consumes: `ModuleHue` from Task 2.
- Produces: `GradientCanvas<Content: View>(hue:content:)` — a full-bleed background wrapper.

- [ ] **Step 1: Implement the primitive**

Views are verified by preview, not unit test. There is no logic here worth a test cycle.

```swift
import SwiftUI

/// The one gradient primitive. Saturated at the top, near-white at the bottom.
/// Adding a module later is a hue token, not a new screen design.
public struct GradientCanvas<Content: View>: View {
    private let hue: ModuleHue
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(hue: ModuleHue, @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: scheme == .dark
                    ? [hue.darkTop, hue.darkBottom]
                    : [hue.top, hue.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            content
        }
    }
}

#Preview("All hues, light") {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(ModuleHue.allCases, id: \.self) { hue in
                GradientCanvas(hue: hue) {
                    Text(hue.rawValue)
                        .foregroundStyle(.white)
                        .padding(.top, 60)
                }
                .frame(width: 200, height: 420)
            }
        }
    }
}

#Preview("All hues, dark") {
    ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(ModuleHue.allCases, id: \.self) { hue in
                GradientCanvas(hue: hue) {
                    Text(hue.rawValue)
                        .foregroundStyle(.white)
                        .padding(.top, 60)
                }
                .frame(width: 200, height: 420)
            }
        }
    }
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Verify the previews render**

Open `GradientCanvas.swift` in Xcode and confirm both previews render six distinct gradients, each fading to near-white (light) or near-black (dark).

- [ ] **Step 3: Confirm the package builds, then commit**

Run: `swift build --package-path LifeOSKit`
Expected: `Build complete!`

```bash
git add LifeOSKit
git commit -m "feat(design): add GradientCanvas primitive"
```

---

### Task 4: Month grid layout maths

The dot grid is the app's central visual claim, and its calendar arithmetic is exactly the kind of thing that silently breaks on month boundaries. Pure function, test-first.

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/MonthGridLayout.swift`
- Create: `LifeOSKit/Tests/DesignSystemTests/MonthGridLayoutTests.swift`

**Interfaces:**
- Produces: `DotState` (enum), `DotCell` (struct with `date: Date?`, `state: DotState`), `MonthGridLayout.cells(monthContaining:calendar:today:status:) -> [DotCell]`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct MonthGridLayoutTests {
    /// Monday-first calendar, so grid columns read M T W T F S S like the reference design.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func augustTwentyTwentySixStartsWithFiveBlankCells() {
        // 1 Aug 2026 is a Saturday. Monday-first columns run M T W T F S S,
        // so Saturday is index 5 ⇒ five leading blanks.
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .noData }
        )
        #expect(cells.prefix(5).allSatisfy { $0.state == .blank })
        #expect(cells[5].date == date(2026, 8, 1))
    }

    /// 1 Feb 2026 is a Sunday — the worst case for a Monday-first grid, and the
    /// only month start that needs a full six blanks. Guards the `% 7` wraparound
    /// in the leading-blank maths, which an August-only test cannot distinguish.
    @Test func monthStartingOnSundayTakesSixBlankCells() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 2, 15),
            calendar: calendar,
            today: date(2026, 2, 15),
            status: { _ in .noData }
        )
        #expect(cells.prefix(6).allSatisfy { $0.state == .blank })
        #expect(cells[6].date == date(2026, 2, 1))
        // 6 blanks + 28 days = 34, padded to 35.
        #expect(cells.count == 35)
    }

    @Test func cellCountCoversWholeMonthPlusPadding() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .noData }
        )
        // 5 blanks + 31 days = 36, padded to a whole number of 7-day rows.
        #expect(cells.count == 42)
        #expect(cells.filter { $0.date != nil }.count == 31)
    }

    @Test func todayOverridesItsStatus() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .onTarget }
        )
        let todayCell = cells.first { $0.date == date(2026, 8, 10) }
        #expect(todayCell?.state == .today)
    }

    @Test func daysAfterTodayAreFutureRegardlessOfStatus() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .onTarget }
        )
        let tomorrow = cells.first { $0.date == date(2026, 8, 11) }
        #expect(tomorrow?.state == .future)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --package-path LifeOSKit --filter MonthGridLayoutTests`
Expected: compile failure — `cannot find 'MonthGridLayout' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Visual state of a single dot. `blank` is layout padding, not a day.
public enum DotState: Sendable, Equatable {
    case onTarget, missed, today, future, noData, blank
}

public struct DotCell: Sendable, Equatable, Identifiable {
    public let id: Int
    public let date: Date?
    public let state: DotState

    /// Explicit and public — a struct's memberwise init is internal by default,
    /// which would make this unconstructible from the app target.
    public init(id: Int, date: Date?, state: DotState) {
        self.id = id
        self.date = date
        self.state = state
    }
}

public enum MonthGridLayout {
    /// Builds a whole number of 7-day rows for the month containing `date`.
    /// `status` is called only for past days; today and future days are
    /// assigned by position so a partially-logged today never renders as a miss.
    public static func cells(
        monthContaining date: Date,
        calendar: Calendar,
        today: Date,
        status: (Date) -> DotState
    ) -> [DotCell] {
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )!
        let dayCount = calendar.range(of: .day, in: .month, for: startOfMonth)!.count

        // How many blanks before day 1, given the calendar's first weekday.
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        let startOfToday = calendar.startOfDay(for: today)
        var cells: [DotCell] = []

        for _ in 0..<leading {
            cells.append(DotCell(id: cells.count, date: nil, state: .blank))
        }

        for day in 1...dayCount {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)!
            let state: DotState = if calendar.isDate(dayDate, inSameDayAs: startOfToday) {
                .today
            } else if dayDate > startOfToday {
                .future
            } else {
                status(dayDate)
            }
            cells.append(DotCell(id: cells.count, date: dayDate, state: state))
        }

        // Pad to a whole number of rows so the grid is rectangular.
        while cells.count % 7 != 0 {
            cells.append(DotCell(id: cells.count, date: nil, state: .blank))
        }

        return cells
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --package-path LifeOSKit --filter MonthGridLayoutTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit
git commit -m "feat(design): add month grid layout with tested calendar maths"
```

---

### Task 5: Dot grid, cards, numerals, tiles, week strip

The remaining view components. Grouped into one task because none carries independent logic — a reviewer would accept or reject them together.

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/DotGrid.swift`
- Create: `LifeOSKit/Sources/DesignSystem/GlassCard.swift`
- Create: `LifeOSKit/Sources/DesignSystem/HeroNumeral.swift`
- Create: `LifeOSKit/Sources/DesignSystem/StatTile.swift`
- Create: `LifeOSKit/Sources/DesignSystem/WeekStrip.swift`

**Interfaces:**
- Consumes: `DotCell`, `DotState`, `ModuleHue`, `LifeOSTokens`.
- Produces: `DotGrid(cells:)`, `GlassCard { }`, `SolidCard { }`, `HeroNumeral(value:unit:label:)`, `StatTile(label:value:unit:progress:)`, `WeekStrip(selection:calendar:today:)`.

- [ ] **Step 1: Implement `DotGrid`**

```swift
import SwiftUI

public struct DotGrid: View {
    private let cells: [DotCell]
    private let dotSize: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(cells: [DotCell], dotSize: CGFloat = 22) {
        self.cells = cells
        self.dotSize = dotSize
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(cells) { cell in
                Circle()
                    .fill(fill(for: cell.state))
                    .overlay {
                        if cell.state == .noData {
                            Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
                        }
                    }
                    .frame(width: dotSize, height: dotSize)
                    .opacity(cell.state == .blank ? 0 : 1)
            }
        }
    }

    private func fill(for state: DotState) -> Color {
        switch state {
        case .onTarget: LifeOSTokens.primaryText.resolve(scheme)
        case .missed:   LifeOSTokens.dotMissed.resolve(scheme)
        case .today:    LifeOSTokens.accent
        case .future:   LifeOSTokens.dotFuture.resolve(scheme)
        case .noData:   .clear
        case .blank:    .clear
        }
    }
}

private let dotGridPreviewCells: [DotCell] = (0..<42).map { index in
    DotCell(id: index, date: nil, state: [.onTarget, .missed, .today, .future, .noData][index % 5])
}

#Preview("Light") {
    DotGrid(cells: dotGridPreviewCells)
        .padding()
        .background(LifeOSTokens.canvas.light)
}

#Preview("Dark") {
    DotGrid(cells: dotGridPreviewCells)
        .padding()
        .background(LifeOSTokens.canvas.dark)
        .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Implement the two card treatments**

```swift
import SwiftUI

/// Frosted card, for use while over the saturated region of a gradient.
public struct GlassCard<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Solid card, for use once the gradient has faded to near-white.
public struct SolidCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.05), radius: 12, y: 4)
            )
    }
}
```

- [ ] **Step 3: Implement `HeroNumeral`**

```swift
import SwiftUI

/// The hero figure on a domain screen. A numeral is never shown without its unit.
public struct HeroNumeral: View {
    private let value: String
    private let unit: String?
    private let label: String

    public init(value: String, unit: String? = nil, label: String) {
        self.value = value
        self.unit = unit
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 96, weight: .semibold, design: .default))
                    .tracking(-3)
                if let unit {
                    Text(unit).font(.system(size: 28, weight: .medium))
                }
            }
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .opacity(0.7)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

/// Shown in place of a `HeroNumeral` when the metric has no data.
/// A missing value must never look like a zero.
public struct HeroEmptyState: View {
    private let label: String
    private let reason: String

    public init(label: String, reason: String) {
        self.label = label
        self.reason = reason
    }

    public var body: some View {
        VStack(spacing: 6) {
            Text("—")
                .font(.system(size: 96, weight: .semibold))
                .opacity(0.35)
            Text(label).font(.system(size: 15, weight: .medium)).opacity(0.7)
            Text(reason).font(.footnote).opacity(0.5)
        }
    }
}
```

- [ ] **Step 4: Implement `StatTile`**

```swift
import SwiftUI

public struct StatTile: View {
    private let label: String
    private let value: String?
    private let unit: String?
    private let progress: Double?
    @Environment(\.colorScheme) private var scheme

    /// `value == nil` renders an em dash, never a zero.
    public init(label: String, value: String?, unit: String? = nil, progress: Double? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .opacity(0.55)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(.system(size: 26, weight: .semibold))
                    .opacity(value == nil ? 0.35 : 1)
                if let unit, value != nil {
                    Text(unit).font(.system(size: 13, weight: .medium)).opacity(0.6)
                }
            }

            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(progress >= 1 ? LifeOSTokens.accent : LifeOSTokens.primaryText.resolve(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 5: Implement `WeekStrip`**

```swift
import SwiftUI

public struct WeekStrip: View {
    @Binding private var selection: Date
    private let calendar: Calendar
    private let today: Date

    public init(selection: Binding<Date>, calendar: Calendar = .current, today: Date = .now) {
        self._selection = selection
        self.calendar = calendar
        self.today = today
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selection)
                let isFuture = calendar.startOfDay(for: day) > calendar.startOfDay(for: today)

                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.5)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isSelected ? LifeOSTokens.accent : .clear))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .opacity(isFuture ? 0.35 : 1)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { if !isFuture { selection = day } }
            }
        }
    }
}
```

- [ ] **Step 6: Verify previews and build**

Run: `swift build --package-path LifeOSKit`
Expected: `Build complete!` with no warnings.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit
git commit -m "feat(design): add dot grid, cards, hero numeral, stat tile, week strip"
```

---

### Task 6: Goal evaluation and streaks

The rule that decides what the app tells you about yourself every morning. Pure logic, test-first, no SwiftData.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/GoalEvaluation.swift`
- Create: `LifeOSKit/Sources/Persistence/Streak.swift`
- Modify: `LifeOSKit/Tests/PersistenceTests/GoalEvaluationTests.swift`
- Create: `LifeOSKit/Tests/PersistenceTests/StreakTests.swift`

**Interfaces:**
- Consumes: `GoalTargets` from Task 1.
- Produces: `DayReading`, `DayStatus` (`.onTarget`/`.missed`/`.noData`), `evaluate(_:against:) -> DayStatus`, `currentStreak(statuses:) -> Int`.

`DayStatus` here is deliberately separate from `DesignSystem.DotState` — `Persistence` must not depend on `DesignSystem`. The app target maps one to the other in Task 9.

- [ ] **Step 1: Write the failing evaluation tests**

Append to `GoalEvaluationTests.swift`:

```swift
    @Test func aDayWithNoMetricsAtAllIsNoData() {
        let reading = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        #expect(evaluate(reading, against: .default) == .noData)
    }

    @Test func threeOfFourGoalsMetIsOnTarget() {
        let reading = DayReading(steps: 9000, sleepMinutes: 430, exerciseMinutes: 45, waterML: 900)
        #expect(evaluate(reading, against: .default) == .onTarget)
    }

    @Test func twoOfFourGoalsMetIsAMiss() {
        let reading = DayReading(steps: 9000, sleepMinutes: 430, exerciseMinutes: 5, waterML: 900)
        #expect(evaluate(reading, against: .default) == .missed)
    }

    @Test func exactlyAtGoalCounts() {
        let reading = DayReading(steps: 8000, sleepMinutes: 420, exerciseMinutes: 30, waterML: 0)
        #expect(evaluate(reading, against: .default) == .onTarget)
    }

    /// A partially-logged day is judged on what it has. Deliberate: otherwise
    /// forgetting to log water would silently promote a bad day to "no data".
    @Test func partialDataIsJudgedNotExcused() {
        let reading = DayReading(steps: 500, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        #expect(evaluate(reading, against: .default) == .missed)
    }

    @Test func requiredCountIsConfigurable() {
        var targets = GoalTargets.default
        targets.requiredCount = 4
        let reading = DayReading(steps: 9000, sleepMinutes: 430, exerciseMinutes: 45, waterML: 900)
        #expect(evaluate(reading, against: targets) == .missed)
    }
```

- [ ] **Step 2: Run and confirm they fail**

Run: `swift test --package-path LifeOSKit --filter GoalEvaluationTests`
Expected: `cannot find 'DayReading' in scope`.

- [ ] **Step 3: Implement evaluation**

Append to `GoalEvaluation.swift`:

```swift
public struct DayReading: Sendable, Equatable {
    public var steps: Int?
    public var sleepMinutes: Int?
    public var exerciseMinutes: Int?
    public var waterML: Double?

    public init(steps: Int?, sleepMinutes: Int?, exerciseMinutes: Int?, waterML: Double?) {
        self.steps = steps
        self.sleepMinutes = sleepMinutes
        self.exerciseMinutes = exerciseMinutes
        self.waterML = waterML
    }

    public var hasAnyData: Bool {
        steps != nil || sleepMinutes != nil || exerciseMinutes != nil || waterML != nil
    }
}

public enum DayStatus: Sendable, Equatable {
    case onTarget, missed, noData
}

/// A day with no metrics at all is excluded from judgement — leaving the watch
/// on the charger is not a failure. A day with *some* data is judged on what
/// it has, so an unlogged metric cannot launder a bad day into a blank one.
public func evaluate(_ reading: DayReading, against targets: GoalTargets) -> DayStatus {
    guard reading.hasAnyData else { return .noData }

    var met = 0
    if let steps = reading.steps, steps >= targets.steps { met += 1 }
    if let sleep = reading.sleepMinutes, sleep >= targets.sleepMinutes { met += 1 }
    if let exercise = reading.exerciseMinutes, exercise >= targets.exerciseMinutes { met += 1 }
    if let water = reading.waterML, water >= targets.waterML { met += 1 }

    return met >= targets.requiredCount ? .onTarget : .missed
}
```

- [ ] **Step 4: Run and confirm they pass**

Run: `swift test --package-path LifeOSKit --filter GoalEvaluationTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Write the failing streak tests**

`LifeOSKit/Tests/PersistenceTests/StreakTests.swift`:

```swift
import Testing
@testable import Persistence

@Suite struct StreakTests {
    @Test func countsConsecutiveOnTargetDaysFromMostRecent() {
        #expect(currentStreak(statuses: [.onTarget, .onTarget, .onTarget, .missed]) == 3)
    }

    @Test func aMissEndsTheStreakImmediately() {
        #expect(currentStreak(statuses: [.missed, .onTarget, .onTarget]) == 0)
    }

    /// A day with no data neither extends nor breaks a streak.
    @Test func noDataDaysAreSkipped() {
        #expect(currentStreak(statuses: [.onTarget, .noData, .onTarget, .missed]) == 2)
    }

    @Test func leadingNoDataDoesNotBreakTheStreak() {
        #expect(currentStreak(statuses: [.noData, .onTarget, .onTarget]) == 2)
    }

    @Test func emptyHistoryIsZero() {
        #expect(currentStreak(statuses: []) == 0)
    }
}
```

- [ ] **Step 6: Run and confirm they fail**

Run: `swift test --package-path LifeOSKit --filter StreakTests`
Expected: `cannot find 'currentStreak' in scope`.

- [ ] **Step 7: Implement streaks**

`LifeOSKit/Sources/Persistence/Streak.swift`:

```swift
import Foundation

/// `statuses` must be ordered most-recent-first.
/// Days with no data are transparent: they neither extend nor break a streak.
public func currentStreak(statuses: [DayStatus]) -> Int {
    var count = 0
    for status in statuses {
        switch status {
        case .onTarget: count += 1
        case .noData:   continue
        case .missed:   return count
        }
    }
    return count
}
```

- [ ] **Step 8: Run the full suite and commit**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, 17 tests.

```bash
git add LifeOSKit
git commit -m "feat(persistence): add goal evaluation and streak arithmetic"
```

---

### Task 7: SwiftData models and container

**Files:**
- Create: `LifeOSKit/Sources/Persistence/DailyMetrics.swift`
- Create: `LifeOSKit/Sources/Persistence/UserGoals.swift`
- Create: `LifeOSKit/Sources/Persistence/SourceRecords.swift`
- Create: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift`

**Interfaces:**
- Produces: `DailyMetrics`, `UserGoals`, `WorkoutRecord`, `SleepRecord` (`@Model` classes); `LifeOSContainer.make(inMemory:) throws -> ModelContainer`; `DailyMetrics.reading` bridging to `DayReading`.

- [ ] **Step 1: Implement `DailyMetrics`**

```swift
import Foundation
import SwiftData

/// One row per calendar day — the join key for the entire app.
/// HealthKit and Whoop are both writers; the UI and the coach are readers.
///
/// Every metric is optional. A missing value and a zero must never be the
/// same thing: in a health app a false zero is worse than a blank.
@Model
public final class DailyMetrics {
    #Unique<DailyMetrics>([\.date])

    /// Always `Calendar.startOfDay`. Never a timestamp.
    public var date: Date

    public var weightKg: Double?
    public var steps: Int?
    public var activeEnergyKcal: Double?
    public var exerciseMinutes: Int?
    public var sleepMinutes: Int?
    public var waterML: Double?
    public var restingHR: Double?
    public var hrvMs: Double?

    public var whoopRecoveryPct: Double?
    public var whoopDayStrain: Double?
    public var whoopSleepPerformancePct: Double?

    public var updatedAt: Date
    public var syncedAt: Date?

    public init(date: Date) {
        self.date = date
        self.updatedAt = .now
    }

    public var reading: DayReading {
        DayReading(
            steps: steps,
            sleepMinutes: sleepMinutes,
            exerciseMinutes: exerciseMinutes,
            waterML: waterML
        )
    }
}
```

- [ ] **Step 2: Implement `UserGoals`**

```swift
import Foundation
import SwiftData

/// Singleton by convention — exactly one row. Editable in Settings.
@Model
public final class UserGoals {
    public var stepsGoal: Int
    public var sleepMinutesGoal: Int
    public var exerciseMinutesGoal: Int
    public var waterMLGoal: Double
    public var requiredCount: Int

    public init(
        stepsGoal: Int = 8000,
        sleepMinutesGoal: Int = 420,
        exerciseMinutesGoal: Int = 30,
        waterMLGoal: Double = 2500,
        requiredCount: Int = 3
    ) {
        self.stepsGoal = stepsGoal
        self.sleepMinutesGoal = sleepMinutesGoal
        self.exerciseMinutesGoal = exerciseMinutesGoal
        self.waterMLGoal = waterMLGoal
        self.requiredCount = requiredCount
    }

    public var targets: GoalTargets {
        GoalTargets(
            steps: stepsGoal,
            sleepMinutes: sleepMinutesGoal,
            exerciseMinutes: exerciseMinutesGoal,
            waterML: waterMLGoal,
            requiredCount: requiredCount
        )
    }
}
```

- [ ] **Step 3: Implement the source records**

```swift
import Foundation
import SwiftData

/// Source records roll *up* into `DailyMetrics`, which is derived state and
/// always safe to recompute from these.
@Model
public final class WorkoutRecord {
    public var externalID: String
    public var start: Date
    public var durationMinutes: Int
    public var activityName: String
    public var energyKcal: Double?

    public init(externalID: String, start: Date, durationMinutes: Int, activityName: String, energyKcal: Double? = nil) {
        self.externalID = externalID
        self.start = start
        self.durationMinutes = durationMinutes
        self.activityName = activityName
        self.energyKcal = energyKcal
    }
}

@Model
public final class SleepRecord {
    public var externalID: String
    public var start: Date
    public var end: Date
    /// The day this sleep is attributed to — the morning you woke up.
    public var attributedDate: Date

    public init(externalID: String, start: Date, end: Date, attributedDate: Date) {
        self.externalID = externalID
        self.start = start
        self.end = end
        self.attributedDate = attributedDate
    }

    public var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}
```

- [ ] **Step 4: Implement the container factory**

```swift
import Foundation
import SwiftData

public enum LifeOSContainer {
    public static let schema = Schema([
        DailyMetrics.self,
        UserGoals.self,
        WorkoutRecord.self,
        SleepRecord.self,
    ])

    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

- [ ] **Step 5: Build and commit**

Run: `swift build --package-path LifeOSKit`
Expected: `Build complete!`

```bash
git add LifeOSKit
git commit -m "feat(persistence): add SwiftData models and container factory"
```

---

### Task 8: Metrics store

Upsert is where a "one row per day" invariant either holds or quietly breaks. Test-first, against a real in-memory container.

**Files:**
- Create: `LifeOSKit/Sources/Persistence/MetricsStore.swift`
- Create: `LifeOSKit/Tests/PersistenceTests/MetricsStoreTests.swift`

**Interfaces:**
- Consumes: `DailyMetrics`, `LifeOSContainer` from Task 7.
- Produces: `MetricsStore(context:)`, `.upsert(date:apply:) throws`, `.metrics(from:to:) throws -> [DailyMetrics]`, `.goals() throws -> UserGoals`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct MetricsStoreTests {
    private func makeStore() throws -> MetricsStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MetricsStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func upsertCreatesARowWhenNoneExists() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 5000 }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].steps == 5000)
    }

    @Test func upsertMutatesTheExistingRowRatherThanAddingASecond() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 5000 }
        try store.upsert(date: day) { $0.weightKg = 77.9 }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].steps == 5000)      // not clobbered
        #expect(rows[0].weightKg == 77.9)
    }

    @Test func upsertNormalisesAnyTimestampToStartOfDay() throws {
        let store = try makeStore()
        let midMorning = day.addingTimeInterval(9 * 3600)
        try store.upsert(date: midMorning) { $0.steps = 100 }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].date == day)
    }

    @Test func upsertStampsUpdatedAt() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 100 }
        let first = try store.metrics(from: day, to: day)[0].updatedAt

        try store.upsert(date: day) { $0.steps = 200 }
        let second = try store.metrics(from: day, to: day)[0].updatedAt

        #expect(second >= first)
    }

    @Test func metricsAreReturnedMostRecentFirst() throws {
        let store = try makeStore()
        let earlier = Calendar.current.date(byAdding: .day, value: -3, to: day)!
        try store.upsert(date: earlier) { $0.steps = 1 }
        try store.upsert(date: day) { $0.steps = 2 }

        let rows = try store.metrics(from: earlier, to: day)
        #expect(rows.map(\.steps) == [2, 1])
    }

    @Test func goalsCreatesDefaultsOnFirstAccessAndReusesThemAfter() throws {
        let store = try makeStore()
        let first = try store.goals()
        first.stepsGoal = 12000

        let second = try store.goals()
        #expect(second.stepsGoal == 12000)
    }
}
```

- [ ] **Step 2: Run and confirm they fail**

Run: `swift test --package-path LifeOSKit --filter MetricsStoreTests`
Expected: `cannot find 'MetricsStore' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import SwiftData

/// The only way anything writes to `DailyMetrics`. Enforces the
/// one-row-per-calendar-day invariant so callers cannot get it wrong.
@MainActor
public struct MetricsStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Fetches or creates the row for `date`'s day and applies `apply` to it.
    /// Fields left untouched by `apply` are preserved — this is a merge, not a
    /// replace, so HealthKit and Whoop can both write the same row safely.
    @discardableResult
    public func upsert(date: Date, apply: (DailyMetrics) -> Void) throws -> DailyMetrics {
        let day = calendar.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date == day })

        let row: DailyMetrics
        if let existing = try context.fetch(descriptor).first {
            row = existing
        } else {
            row = DailyMetrics(date: day)
            context.insert(row)
        }

        apply(row)
        row.updatedAt = .now
        try context.save()
        return row
    }

    /// Most-recent-first, matching the order `currentStreak` expects.
    public func metrics(from start: Date, to end: Date) throws -> [DailyMetrics] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.startOfDay(for: end)
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date >= lower && $0.date <= upper },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// There is exactly one goals row. Created with spec defaults on first access.
    public func goals() throws -> UserGoals {
        if let existing = try context.fetch(FetchDescriptor<UserGoals>()).first {
            return existing
        }
        let goals = UserGoals()
        context.insert(goals)
        try context.save()
        return goals
    }
}
```

- [ ] **Step 4: Run and confirm they pass**

Run: `swift test --package-path LifeOSKit --filter MetricsStoreTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Run the full suite and commit**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, 23 tests.

```bash
git add LifeOSKit
git commit -m "feat(persistence): add MetricsStore with day-normalised upsert"
```

---

### Task 9: Seed data and app shell

Replaces the Hello World scaffold with the real tab structure, and seeds 60 days so every screen has something to render before any integration exists.

**Files:**
- Create: `LifeOSKit/Sources/Persistence/SeedData.swift`
- Create: `LIfeOS/RootView.swift`
- Modify: `LIfeOS/LIfeOSApp.swift`
- Delete: `LIfeOS/ContentView.swift`

**Interfaces:**
- Consumes: `MetricsStore`, `LifeOSContainer`.
- Produces: `SeedData.populate(store:days:) throws`; `RootView` with five tabs.

- [ ] **Step 1: Implement seed data**

```swift
import Foundation

/// Deterministic, plausible data so screens can be built and reviewed before
/// HealthKit and Whoop exist. Seeded only when the store is empty.
public enum SeedData {
    @MainActor
    public static func populate(store: MetricsStore, days: Int = 60, from today: Date = .now) throws {
        let calendar = Calendar.current

        for offset in 0..<days {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            // Deterministic pseudo-variation — no randomness, so previews are stable.
            let wobble = Double((offset * 37) % 100) / 100.0
            let slowLoss = Double(offset) * 0.02

            try store.upsert(date: date) { row in
                row.weightKg = 77.9 + slowLoss + (wobble - 0.5) * 0.6
                row.steps = Int(5_500 + wobble * 7_000)
                row.activeEnergyKcal = 320 + wobble * 500
                row.exerciseMinutes = Int(12 + wobble * 55)
                row.sleepMinutes = Int(360 + wobble * 130)
                row.restingHR = 52 + wobble * 9
                row.hrvMs = 45 + wobble * 55

                // Water is only sometimes logged, so the UI's missing-data path
                // is exercised rather than theoretical.
                row.waterML = offset % 3 == 0 ? nil : 1_400 + wobble * 1_600

                // Whoop stays empty until Plan 3 — Recovery must render its
                // empty state convincingly before the integration exists.
                row.whoopRecoveryPct = nil
                row.whoopDayStrain = nil
                row.whoopSleepPerformancePct = nil
            }
        }
    }
}
```

- [ ] **Step 2: Implement `RootView`**

```swift
import SwiftUI
import DesignSystem
import Persistence

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var showQuickLog = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                Tab("Today", systemImage: "circle.grid.3x3.fill") { TodayScreen() }
                Tab("Body", systemImage: "figure") { BodyScreen() }
                Tab("Activity", systemImage: "flame.fill") { ActivityScreen() }
                Tab("Recovery", systemImage: "bolt.heart.fill") { RecoveryScreen() }
                Tab("Settings", systemImage: "gearshape.fill") { SettingsScreen() }
            }

            Button {
                showQuickLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(LifeOSTokens.primaryText.resolve(scheme)))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 72)
            .accessibilityLabel("Quick log")
        }
        .sheet(isPresented: $showQuickLog) { QuickLogSheet() }
    }
}
```

- [ ] **Step 3: Wire up the app entry point**

`LIfeOS/LIfeOSApp.swift`:

```swift
import SwiftUI
import SwiftData
import Persistence

@main
struct LIfeOSApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try LifeOSContainer.make()
        } catch {
            // A container that cannot open is unrecoverable and always a
            // schema bug, never a user condition. Fail loudly during development.
            fatalError("Failed to create the model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await seedIfEmpty() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func seedIfEmpty() async {
        let store = MetricsStore(context: container.mainContext)
        do {
            let existing = try store.metrics(from: .distantPast, to: .now)
            guard existing.isEmpty else { return }
            try SeedData.populate(store: store)
        } catch {
            print("Seed failed: \(error)")
        }
    }
}
```

- [ ] **Step 4: Delete the scaffold**

```bash
git rm LIfeOS/ContentView.swift
```

Then remove its file reference in Xcode if the build complains about a missing file.

- [ ] **Step 5: Create empty screen stubs so the project compiles**

Six files under `LIfeOS/Screens/`, each replaced with its real implementation in Tasks 10–12.

`TodayScreen.swift`:
```swift
import SwiftUI

struct TodayScreen: View {
    var body: some View { Text("Today") }
}
```

`BodyScreen.swift`:
```swift
import SwiftUI

struct BodyScreen: View {
    var body: some View { Text("Body") }
}
```

`ActivityScreen.swift`:
```swift
import SwiftUI

struct ActivityScreen: View {
    var body: some View { Text("Activity") }
}
```

`RecoveryScreen.swift`:
```swift
import SwiftUI

struct RecoveryScreen: View {
    var body: some View { Text("Recovery") }
}
```

`SettingsScreen.swift`:
```swift
import SwiftUI

struct SettingsScreen: View {
    var body: some View { Text("Settings") }
}
```

`QuickLogSheet.swift`:
```swift
import SwiftUI

struct QuickLogSheet: View {
    var body: some View { Text("Quick log") }
}
```

- [ ] **Step 6: Build, run, and commit**

```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Run in the simulator and confirm five tabs and a floating dark FAB.

```bash
git add -A
git commit -m "feat(app): replace scaffold with tab shell, FAB, and seeded data"
```

---

### Task 10: Today screen

**Files:**
- Modify: `LIfeOS/Screens/TodayScreen.swift`

**Interfaces:**
- Consumes: `DotGrid`, `MonthGridLayout`, `WeekStrip`, `StatTile`, `SolidCard`, `MetricsStore`, `evaluate`, `currentStreak`.

- [ ] **Step 1: Implement the screen**

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

struct TodayScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DailyMetrics.date, order: .reverse) private var metrics: [DailyMetrics]
    @Query private var goalRows: [UserGoals]

    @Environment(\.colorScheme) private var scheme
    @State private var selection = Date()
    private let calendar = Calendar.current

    private var targets: GoalTargets { goalRows.first?.targets ?? .default }

    /// Day-keyed statuses, computed once per render rather than per dot.
    private var statusByDay: [Date: DayStatus] {
        Dictionary(uniqueKeysWithValues: metrics.map {
            ($0.date, evaluate($0.reading, against: targets))
        })
    }

    private var today: DailyMetrics? {
        metrics.first { calendar.isDateInToday($0.date) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                WeekStrip(selection: $selection)

                SolidCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(selection.formatted(.dateTime.month(.wide).year()))
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(streak) day streak")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(LifeOSTokens.accent)
                        }
                        DotGrid(cells: cells)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SolidCard {
                        StatTile(label: "Steps", value: today?.steps.map { "\($0)" },
                                 progress: today?.steps.map { Double($0) / Double(targets.steps) })
                    }
                    SolidCard {
                        StatTile(label: "Sleep", value: today?.sleepMinutes.map(formatDuration), unit: nil,
                                 progress: today?.sleepMinutes.map { Double($0) / Double(targets.sleepMinutes) })
                    }
                    SolidCard {
                        StatTile(label: "Weight", value: today?.weightKg.map { String(format: "%.1f", $0) }, unit: "kg")
                    }
                    SolidCard {
                        StatTile(label: "Recovery", value: today?.whoopRecoveryPct.map { "\(Int($0))" }, unit: "%")
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .background(LifeOSTokens.canvas.resolve(scheme))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: -6) {
            Text(selection.formatted(.dateTime.day()))
                .font(.system(size: 92, weight: .bold))
                .tracking(-4)
            HStack(alignment: .firstTextBaseline) {
                Text(selection.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text(selection.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
    }

    private var cells: [DotCell] {
        MonthGridLayout.cells(
            monthContaining: selection,
            calendar: calendar,
            today: .now,
            status: { date in
                switch statusByDay[calendar.startOfDay(for: date)] {
                case .onTarget: .onTarget
                case .missed:   .missed
                case .noData, nil: .noData
                }
            }
        )
    }

    private var streak: Int {
        currentStreak(statuses: metrics.map { evaluate($0.reading, against: targets) })
    }

    private func formatDuration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }
}
```

- [ ] **Step 2: Build and inspect**

Run in the simulator. Confirm: an oversized date, a week strip, a month of dots with today in orange, a streak count, and four tiles. Because seed data leaves water unlogged every third day and Whoop empty, confirm the Recovery tile shows an em dash — **not a zero**.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS
git commit -m "feat(app): build the Today screen"
```

---

### Task 11: Body, Activity, and Recovery screens

Three domain screens sharing one structure: gradient canvas, hero numeral, tiles. Grouped because they are the same screen three times with different hues and fields — a reviewer accepts or rejects the pattern, not each instance.

**Files:**
- Modify: `LIfeOS/Screens/BodyScreen.swift`, `ActivityScreen.swift`, `RecoveryScreen.swift`

- [ ] **Step 1: Implement `BodyScreen`**

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

struct BodyScreen: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var metrics: [DailyMetrics]

    private var latest: DailyMetrics? { metrics.first { $0.weightKg != nil } }

    /// Change over the last seven days, nil when there isn't enough history.
    private var weeklyDelta: Double? {
        let weighed = metrics.compactMap { row in row.weightKg.map { (row.date, $0) } }
        guard let newest = weighed.first,
              let weekAgo = weighed.first(where: { $0.0 <= newest.0.addingTimeInterval(-6 * 86_400) })
        else { return nil }
        return newest.1 - weekAgo.1
    }

    var body: some View {
        GradientCanvas(hue: .body) {
            ScrollView {
                VStack(spacing: 28) {
                    if let weight = latest?.weightKg {
                        HeroNumeral(value: String(format: "%.1f", weight), unit: "kg", label: "Bodyweight")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    } else {
                        HeroEmptyState(label: "Bodyweight", reason: "No weigh-in recorded")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    }

                    if let delta = weeklyDelta {
                        GlassCard {
                            HStack {
                                Text("This week").font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) kg")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LifeOSTokens.accent)
                            }
                        }
                        .foregroundStyle(.white)
                    }

                    SolidCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LAST 14 DAYS")
                                .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                            WeightBars(points: Array(metrics.prefix(14).reversed()))
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
    }
}

/// The vertical bar chart from the reference design.
private struct WeightBars: View {
    let points: [DailyMetrics]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let weights = points.compactMap(\.weightKg)
        let low = weights.min() ?? 0
        let high = weights.max() ?? 1
        let span = max(high - low, 0.1)

        HStack(alignment: .bottom, spacing: 5) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 2)
                    .fill(point.weightKg == nil
                          ? LifeOSTokens.dotMissed.resolve(scheme)
                          : LifeOSTokens.primaryText.resolve(scheme))
                    .frame(height: point.weightKg.map { 20 + ($0 - low) / span * 60 } ?? 6)
            }
        }
        .frame(height: 84)
    }
}
```

- [ ] **Step 2: Implement `ActivityScreen`**

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

struct ActivityScreen: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var metrics: [DailyMetrics]
    private var today: DailyMetrics? { metrics.first }

    var body: some View {
        GradientCanvas(hue: .activity) {
            ScrollView {
                VStack(spacing: 28) {
                    if let steps = today?.steps {
                        HeroNumeral(value: steps.formatted(), label: "Steps")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    } else {
                        HeroEmptyState(label: "Steps", reason: "No movement recorded today")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    }

                    HStack(spacing: 10) {
                        GlassCard {
                            StatTile(label: "Active", value: today?.exerciseMinutes.map { "\($0)" }, unit: "min")
                        }
                        GlassCard {
                            StatTile(label: "Energy", value: today?.activeEnergyKcal.map { "\(Int($0))" }, unit: "kcal")
                        }
                        GlassCard {
                            StatTile(label: "Resting HR", value: today?.restingHR.map { "\(Int($0))" }, unit: "bpm")
                        }
                    }
                    .foregroundStyle(.white)
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
    }
}
```

- [ ] **Step 3: Implement `RecoveryScreen`**

Whoop arrives in Plan 3, so this screen ships as a convincing empty state. That is deliberate — the empty state is the one a real user hits before connecting, and building it now means it gets designed rather than bolted on.

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

struct RecoveryScreen: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var metrics: [DailyMetrics]
    private var today: DailyMetrics? { metrics.first }

    var body: some View {
        GradientCanvas(hue: .recovery) {
            ScrollView {
                VStack(spacing: 28) {
                    if let recovery = today?.whoopRecoveryPct {
                        HeroNumeral(value: "\(Int(recovery))", unit: "%", label: "Recovery")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    } else {
                        HeroEmptyState(label: "Recovery", reason: "Connect Whoop in Settings")
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                    }

                    HStack(spacing: 10) {
                        GlassCard { StatTile(label: "HRV", value: today?.hrvMs.map { "\(Int($0))" }, unit: "ms") }
                        GlassCard { StatTile(label: "Strain", value: today?.whoopDayStrain.map { String(format: "%.1f", $0) }) }
                        GlassCard { StatTile(label: "Sleep", value: today?.sleepMinutes.map { "\($0 / 60)h \($0 % 60)m" }) }
                    }
                    .foregroundStyle(.white)
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
    }
}
```

- [ ] **Step 4: Build and inspect all three**

Confirm each screen's gradient matches its module, frosted cards read clearly against the saturated top, and the Recovery hero shows its empty state rather than `0%`.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS
git commit -m "feat(app): build Body, Activity, and Recovery screens"
```

---

### Task 12: Settings and quick log

Closes the loop: goals become editable, so the dot grid's rule is under the user's control rather than hard-coded, and the FAB gets the two metrics that have no automatic source.

**Files:**
- Modify: `LIfeOS/Screens/SettingsScreen.swift`, `LIfeOS/Screens/QuickLogSheet.swift`

- [ ] **Step 1: Implement `SettingsScreen`**

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query private var goalRows: [UserGoals]

    var body: some View {
        NavigationStack {
            Form {
                if let goals = goalRows.first {
                    GoalsSection(goals: goals)
                }

                Section("Connections") {
                    LabeledContent("Apple Health", value: "Not connected")
                    LabeledContent("Whoop", value: "Not connected")
                    LabeledContent("Supabase", value: "Not configured")
                }
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .navigationTitle("Settings")
        }
        // Guarantees the singleton row exists before the form tries to bind to it.
        .task { _ = try? MetricsStore(context: context).goals() }
    }
}

/// Split out so `@Bindable` can take a non-optional model — binding through an
/// optional in a `Form` does not compile cleanly.
private struct GoalsSection: View {
    @Bindable var goals: UserGoals

    var body: some View {
        Section("Daily goals") {
            Stepper("Steps: \(goals.stepsGoal)",
                    value: $goals.stepsGoal, in: 1000...30000, step: 500)
            Stepper("Sleep: \(goals.sleepMinutesGoal / 60)h \(goals.sleepMinutesGoal % 60)m",
                    value: $goals.sleepMinutesGoal, in: 240...660, step: 15)
            Stepper("Exercise: \(goals.exerciseMinutesGoal) min",
                    value: $goals.exerciseMinutesGoal, in: 5...180, step: 5)
            Stepper("Water: \(Int(goals.waterMLGoal)) ml",
                    value: $goals.waterMLGoal, in: 500...6000, step: 250)
            Stepper("Goals needed for a good day: \(goals.requiredCount) of 4",
                    value: $goals.requiredCount, in: 1...4)
        }
    }
}
```

- [ ] **Step 2: Implement `QuickLogSheet`**

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// V1 logs only water and weight — the two metrics with no automatic source.
/// Writes to local `DailyMetrics` only; the app requests no HealthKit write
/// permissions in V1.
struct QuickLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var waterML = 250.0
    @State private var weightText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Water") {
                    Stepper("\(Int(waterML)) ml", value: $waterML, in: 50...2000, step: 50)
                    Button("Add \(Int(waterML)) ml") { addWater() }
                }
                Section("Weight") {
                    TextField("kg", text: $weightText).keyboardType(.decimalPad)
                    Button("Save weight") { saveWeight() }
                        .disabled(Double(weightText) == nil)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Quick log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addWater() {
        perform { store in
            try store.upsert(date: .now) { $0.waterML = ($0.waterML ?? 0) + waterML }
        }
    }

    private func saveWeight() {
        guard let kg = Double(weightText) else { return }
        perform { store in
            try store.upsert(date: .now) { $0.weightKg = kg }
        }
    }

    private func perform(_ work: (MetricsStore) throws -> Void) {
        do {
            try work(MetricsStore(context: context))
            dismiss()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 3: Verify the loop end to end**

In the simulator: open the FAB, add 250 ml of water, dismiss, and confirm the Today screen's dot for today reflects the change once the water goal is crossed. Change the steps goal in Settings and confirm the dot grid re-evaluates.

- [ ] **Step 4: Run everything and commit**

```bash
swift test --package-path LifeOSKit
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build | tail -5
```

Expected: 23 tests pass, `** BUILD SUCCEEDED **`.

```bash
git add -A
git commit -m "feat(app): add settings goal editing and quick log"
```

---

## Done when

- `swift test --package-path LifeOSKit` passes with 23 tests.
- The app runs with five tabs, each rendering seeded data in its own hue.
- Today shows a month dot grid, a live streak, and four tiles.
- Recovery shows a designed empty state, not a zero.
- Editing a goal in Settings changes which dots are filled.
- Logging water via the FAB updates Today.

## Not in this plan

HealthKit (Plan 2). Whoop OAuth, Supabase schema, Edge Functions, sync (Plan 3). The AI coach, nutrition, habits, goals, journal, notes, money, content planner (V2–V7 specs). Screen time (dropped — see spec §2).
