# Today as the Default Tab, with Interactive Day Dots — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Today the app's stated default tab, and make each dot in its month grid open a sheet showing that day's metrics and habits — with today's habits tickable from it.

**Architecture:** `DotGrid` gains an optional `onTap` closure, so the month grid becomes interactive while the habit strips on the Plan tab are untouched. `TodayViewModel` grows a second snapshot (`DayDetailSnapshot`) built from `MetricsStore` and `PlanStore` together; the sheet renders plain values and never sees a SwiftData object. Tab selection moves from an implicit ordering accident to an explicit `@State` value.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`). Two modules: the `LIfeOS` app target and the `LifeOSKit` local package (`DesignSystem`, `Persistence`, `Integrations`).

**Spec:** `docs/superpowers/specs/2026-08-12-today-default-tab-and-interactive-dots-design.md`

## Global Constraints

- **Habits must not change dot colour.** `LifeOSKit/Sources/Persistence/GoalEvaluation.swift` is not modified by any task in this plan. A dot's fill stays a function of steps, sleep, exercise and water.
- **No schema changes.** `PlanEntry`, `HabitTick`, `DailyMetrics` and `LifeOSContainer.schema` are not modified.
- **Copy rule for the habit section:** the header is a bare count — `"2 of 4 habits"`. Never a percentage, never a grade, never the words "missed" or "failed". A past day's sheet lists habits that may not have existed on that date, so the copy must not read as a verdict on the day.
- **Views below `RootView` never touch SwiftData.** They receive plain-value snapshots. This is the existing rule stated at `LIfeOS/App/RootView.swift:5-7`.
- **LifeOSKit builds for macOS** so `swift test` runs without a simulator (see the comment at `LifeOSKit/Sources/DesignSystem/Tokens.swift:44`). Nothing added to `DesignSystem` or `Persistence` may use a UIKit-only API.
- **Read failures use `assertionFailure` and leave the previous value in place**, per the existing convention at `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift:73-77`. Never blank the screen for something the user cannot act on.
- **New `.swift` files under `LIfeOS/` need no Xcode project edit.** The project uses `PBXFileSystemSynchronizedRootGroup`, so files on disk are compiled automatically.

**Commands used throughout:**

```bash
# Package tests (fast, no simulator)
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test

# App target build
xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj \
  -scheme LIfeOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

---

## File Structure

**Modify:**

| File | Responsibility after this plan |
|---|---|
| `LIfeOS/App/RootView.swift` | Owns `AppTab`, binds tab selection, presents the day sheet |
| `LIfeOS/App/AppShell.swift` | Persists completed onboarding |
| `LIfeOS/Features/Today/View/TodayScreen.swift` | Forwards day selection upward; stays a pure function of inputs |
| `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift` | Builds both the month snapshot and the day-detail snapshot; writes habit ticks |
| `LifeOSKit/Sources/DesignSystem/DotGrid.swift` | Renders dots; optionally makes them buttons; labels them for VoiceOver |
| `LifeOSKit/Sources/DesignSystem/MonthCalendarView.swift` | Forwards `onTap` to the grid |
| `LifeOSKit/Sources/Persistence/PlanStore.swift` | Adds a one-fetch read of a single day's ticks |

**Create:**

| File | Responsibility |
|---|---|
| `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift` | The value type the day sheet renders |
| `LIfeOS/Features/Today/View/DayDetailSheet.swift` | The day sheet's layout |
| `LifeOSKit/Tests/PersistenceTests/PlanStoreTests.swift` | Tests for the new store method |

---

## Task 1: Deterministic default tab

Today already renders first, but only because `Tab("Today", …)` is written first in the `TabView` body. This task makes it a stated value, and stops a relaunch from dropping a returning user into onboarding.

**Files:**
- Modify: `LIfeOS/App/RootView.swift:37-83`
- Modify: `LIfeOS/App/AppShell.swift:15`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `RootView.AppTab` (private; no later task references it). Task 6 modifies the same `TabView` body, so it must be applied after this one.

- [ ] **Step 1: Add the tab identity and selection binding to `RootView`**

Add this above `var body` in `LIfeOS/App/RootView.swift`, next to the other `@State` properties:

```swift
    /// The tab bar's selection, stated rather than inferred from ordering.
    /// Deliberately not persisted: the requirement is that a cold launch lands
    /// on Today, and non-persisted `@State` delivers exactly that. Selection
    /// still survives backgrounding, because the scene stays alive.
    private enum AppTab: Hashable { case today, body, money, plan }

    @State private var tab: AppTab = .today
```

- [ ] **Step 2: Bind the `TabView` and give every tab a value**

In `LIfeOS/App/RootView.swift`, change `TabView {` to `TabView(selection: $tab) {`, and add a `value:` argument to each of the four `Tab` initialisers. Only the `Tab(...)` lines change; every tab's content closure stays exactly as it is:

```swift
            TabView(selection: $tab) {
                Tab("Today", systemImage: "circle.grid.3x3.fill", value: AppTab.today) {
                    // ...unchanged...
                }
                Tab("Body", systemImage: "figure", value: AppTab.body) {
                    // ...unchanged...
                }
                Tab("Money", systemImage: "dollarsign.circle.fill", value: AppTab.money) {
                    // ...unchanged...
                }
                Tab("Plan", systemImage: "checklist", value: AppTab.plan) {
                    // ...unchanged...
                }
            }
```

- [ ] **Step 3: Persist completed onboarding in `AppShell`**

In `LIfeOS/App/AppShell.swift`, replace line 15:

```swift
    @State private var hasFinishedOnboarding = false
```

with:

```swift
    /// Persisted: finishing onboarding is a fact about the user, not about this
    /// launch. Without this, any relaunch that cannot restore a Supabase session
    /// re-runs the intro flow instead of opening Today.
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
```

Leave `isGuest` on line 19 as plain `@State`. The comment at `AppShell.swift:16-18` explains why the "Skip for now" bypass must not survive a relaunch, and that reasoning is unchanged.

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Verify in the simulator**

Launch the app. Confirm it opens on Today. Switch to Money, force-quit, relaunch — it must open on Today again, and must not show the onboarding intro.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/App/RootView.swift LIfeOS/App/AppShell.swift
git commit -m "fix: make Today the stated default tab, and remember onboarding

Tab selection was a consequence of Today being written first in the
TabView body. It is now an explicit initial value. Completed onboarding
persists, so a relaunch without a live session opens Today rather than
the intro flow."
```

---

## Task 2: `PlanStore.tickedHabitIDs(on:)`

The sheet needs "which habits were done on this day" as one question. `recentTicks(for:days:endingOn:)` answers it per entry, so building a day's rows through it costs one fetch per habit.

**Files:**
- Create: `LifeOSKit/Tests/PersistenceTests/PlanStoreTests.swift`
- Modify: `LifeOSKit/Sources/Persistence/PlanStore.swift` (add after `recentTicks`, around line 85)

**Interfaces:**
- Consumes: existing `PlanStore.add(kind:title:…)`, `PlanStore.toggleTick(for:on:)`, `LifeOSContainer.make(inMemory:)`.
- Produces: `public func tickedHabitIDs(on date: Date) throws -> Set<UUID>` on `PlanStore`. Task 4 calls it.

- [ ] **Step 1: Write the failing tests**

Create `LifeOSKit/Tests/PersistenceTests/PlanStoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct PlanStoreTests {
    /// Fixed to UTC so the day-boundary test means the same thing everywhere.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func makeStore() throws -> PlanStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return PlanStore(context: ModelContext(container), calendar: calendar)
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
    }

    private var nextDay: Date {
        calendar.date(byAdding: .day, value: 1, to: day)!
    }

    @Test func returnsOnlyTheHabitsTickedOnThatDay() throws {
        let store = try makeStore()
        let read = try store.add(kind: .habit, title: "Read")
        let gym = try store.add(kind: .habit, title: "Gym")
        _ = try store.add(kind: .habit, title: "Water")   // exists, never ticked

        try store.toggleTick(for: read, on: day)
        try store.toggleTick(for: gym, on: day)

        #expect(try store.tickedHabitIDs(on: day) == Set([read.id, gym.id]))
    }

    @Test func isEmptyForADayWithNoTicks() throws {
        let store = try makeStore()
        let read = try store.add(kind: .habit, title: "Read")
        try store.toggleTick(for: read, on: day)

        #expect(try store.tickedHabitIDs(on: nextDay).isEmpty)
    }

    /// The `startOfDay` boundary. A tick logged just before midnight belongs to
    /// the day it was logged on, not to the one starting a minute later.
    @Test func aTickLateInTheEveningBelongsToThatDay() throws {
        let store = try makeStore()
        let read = try store.add(kind: .habit, title: "Read")
        let lateEvening = day.addingTimeInterval(23 * 3600 + 59 * 60)

        try store.toggleTick(for: read, on: lateEvening)

        #expect(try store.tickedHabitIDs(on: day) == Set([read.id]))
        #expect(try store.tickedHabitIDs(on: nextDay).isEmpty)
    }

    /// Un-ticking must actually remove the id, not just flip a flag somewhere.
    @Test func unTickingRemovesTheHabitFromTheDay() throws {
        let store = try makeStore()
        let read = try store.add(kind: .habit, title: "Read")

        try store.toggleTick(for: read, on: day)
        try store.toggleTick(for: read, on: day)

        #expect(try store.tickedHabitIDs(on: day).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test --filter PlanStoreTests
```
Expected: compile failure — `value of type 'PlanStore' has no member 'tickedHabitIDs'`.

- [ ] **Step 3: Implement the method**

In `LifeOSKit/Sources/Persistence/PlanStore.swift`, add this immediately after `recentTicks(for:days:endingOn:)` (which ends at line 85) and before the `streak` doc comment:

```swift
    /// Every habit ticked on `date`, in one fetch. `recentTicks` answers the
    /// same question per entry, so assembling a whole day through it would cost
    /// one query per habit.
    public func tickedHabitIDs(on date: Date) throws -> Set<UUID> {
        let day = calendar.startOfDay(for: date)
        let ticks = try context.fetch(
            FetchDescriptor<HabitTick>(predicate: #Predicate { $0.date == day })
        )
        return Set(ticks.map(\.entryID))
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test --filter PlanStoreTests
```
Expected: 4 tests, all passing.

- [ ] **Step 5: Run the whole package suite for regressions**

Run:
```bash
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/PlanStore.swift LifeOSKit/Tests/PersistenceTests/PlanStoreTests.swift
git commit -m "feat(persistence): read one day's habit ticks in a single fetch

recentTicks answers this per entry, so a day's worth of rows would cost
a query per habit."
```

---

## Task 3: Make `DotGrid` optionally interactive

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/DotGrid.swift` (whole file)
- Modify: `LifeOSKit/Sources/DesignSystem/MonthCalendarView.swift:93-118`
- Modify: `LifeOSKit/Tests/DesignSystemTests/MonthGridLayoutTests.swift` (add one test)

**Interfaces:**
- Consumes: existing `DotCell` (`id: Int`, `date: Date?`, `state: DotState`) and `DotState` (`.onTarget`, `.missed`, `.today`, `.future`, `.noData`, `.blank`) from `MonthGridLayout.swift`.
- Produces:
  - `DotGrid.init(cells:dotSize:spacing:onTap:)` where `onTap: ((DotCell) -> Void)? = nil`
  - `MonthCalendarView.init(date:cells:calendar:today:onTap:)` where `onTap: ((DotCell) -> Void)? = nil`

  Both new parameters are trailing with a `nil` default, so `PlanScreen.swift:96` — the only other `DotGrid` call site in the codebase — compiles and behaves identically.

- [ ] **Step 1: Write the failing test for the nullability contract**

Tappability is gated on `cell.date != nil`. That makes the field's nullability a contract rather than a convenience, so it gets a test. Add this test inside `@Suite struct MonthGridLayoutTests` in `LifeOSKit/Tests/DesignSystemTests/MonthGridLayoutTests.swift`:

```swift
    /// `DotGrid` decides whether a dot is tappable by checking `date != nil`,
    /// so padding cells and only padding cells must lack a date. A real day
    /// with a nil date would be silently unopenable.
    @Test func onlyPaddingCellsLackADate() {
        let cells = MonthGridLayout.cells(
            monthContaining: date(2026, 8, 10),
            calendar: calendar,
            today: date(2026, 8, 10),
            status: { _ in .noData }
        )
        #expect(cells.allSatisfy { ($0.date == nil) == ($0.state == .blank) })
    }
```

- [ ] **Step 2: Run it and confirm it passes**

Run:
```bash
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test --filter MonthGridLayoutTests
```
Expected: PASS. This test documents behaviour `MonthGridLayout` already has; it is a regression guard for the invariant Task 3 is about to depend on, not a driver for new code. If it fails, stop — the layout is wrong and the rest of this task is unsafe.

- [ ] **Step 3: Rewrite `DotGrid.swift` with the tap affordance**

Replace the whole of `LifeOSKit/Sources/DesignSystem/DotGrid.swift` with:

```swift
import SwiftUI

public struct DotGrid: View {
    private let cells: [DotCell]
    /// `nil` lets each dot expand to fill its column, which is how the month
    /// view reads as a dense block. A fixed size is for inline uses that must
    /// not grow, like a streak strip inside a card.
    private let dotSize: CGFloat?
    /// Built once in `init` rather than per `body`. The grid redraws on scroll,
    /// and rebuilding the column array each pass is pure allocation churn.
    private let columns: [GridItem]
    /// Nil leaves the grid a pure readout, which is what the habit strips on the
    /// Plan tab want. The month grid passes a closure and becomes navigable.
    private let onTap: ((DotCell) -> Void)?
    @Environment(\.colorScheme) private var scheme

    public init(
        cells: [DotCell],
        dotSize: CGFloat? = 22,
        spacing: CGFloat = 8,
        onTap: ((DotCell) -> Void)? = nil
    ) {
        self.cells = cells
        self.dotSize = dotSize
        self.columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
        self.onTap = onTap
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cells) { cell in
                if let onTap, isTappable(cell) {
                    Button { onTap(cell) } label: { dot(for: cell) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(for: cell))
                } else {
                    dot(for: cell)
                        .accessibilityLabel(label(for: cell))
                        // Padding cells are layout, not days. Announcing them
                        // would put six silent stops in front of every month.
                        .accessibilityHidden(cell.date == nil)
                }
            }
        }
    }

    /// Padding cells are not days, and a day that has not happened yet has
    /// nothing to open. Both stay inert rather than presenting an empty sheet.
    private func isTappable(_ cell: DotCell) -> Bool {
        cell.date != nil && cell.state != .future && cell.state != .blank
    }

    private func label(for cell: DotCell) -> String {
        guard let date = cell.date else { return "" }
        return "\(date.formatted(.dateTime.day().month(.wide))), \(description(of: cell.state))"
    }

    private func description(of state: DotState) -> String {
        switch state {
        case .onTarget: "on target"
        case .missed:   "off target"
        case .today:    "today"
        case .future:   "upcoming"
        case .noData:   "no data"
        case .blank:    ""
        }
    }

    @ViewBuilder
    private func dot(for cell: DotCell) -> some View {
        let shape = Circle()
            .fill(fill(for: cell.state))
            .overlay {
                switch cell.state {
                case .missed:
                    // Hollow, per the spec: a missed day must read differently
                    // from a day that has not happened yet. Two greys of
                    // slightly different value did not carry that.
                    Circle().strokeBorder(
                        LifeOSTokens.primaryText.resolve(scheme).opacity(0.38),
                        lineWidth: max(1, dotSize.map { $0 / 14 } ?? 1.6)
                    )
                case .noData:
                    Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1)
                default:
                    EmptyView()
                }
            }

        if let dotSize {
            shape.frame(width: dotSize, height: dotSize)
        } else {
            shape.aspectRatio(1, contentMode: .fit)
        }
    }

    private func fill(for state: DotState) -> Color {
        switch state {
        case .onTarget: LifeOSTokens.primaryText.resolve(scheme)
        case .missed:   .clear
        case .today:    LifeOSTokens.accent
        case .future:   LifeOSTokens.dotFuture.resolve(scheme)
        case .noData:   .clear
        case .blank:    LifeOSTokens.dotPadding.resolve(scheme)
        }
    }
}

private let dotGridPreviewCells: [DotCell] = (0..<42).map { index in
    DotCell(id: index, date: nil, state: [.onTarget, .missed, .today, .future, .noData][index % 5])
}

/// Dated cells, because the interactive preview needs `date != nil` to show any
/// tap affordance at all.
private let dotGridDatedPreviewCells: [DotCell] = (0..<42).map { index in
    DotCell(
        id: index,
        date: Calendar.current.date(byAdding: .day, value: index, to: .now),
        state: [.onTarget, .missed, .today, .future, .noData][index % 5]
    )
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

#Preview("Interactive") {
    DotGrid(cells: dotGridDatedPreviewCells, dotSize: nil) { cell in
        print("tapped \(String(describing: cell.date))")
    }
    .padding()
    .background(LifeOSTokens.canvas.light)
}
```

- [ ] **Step 4: Forward `onTap` through `MonthCalendarView`**

In `LifeOSKit/Sources/DesignSystem/MonthCalendarView.swift`, replace the `MonthCalendarView` struct body (lines 93-118) with:

```swift
public struct MonthCalendarView: View {
    private let date: Date
    private let cells: [DotCell]
    private let calendar: Calendar
    private let today: Date
    private let onTap: ((DotCell) -> Void)?
    private let spacing: CGFloat = 6

    public init(
        date: Date,
        cells: [DotCell],
        calendar: Calendar = .current,
        today: Date = .now,
        onTap: ((DotCell) -> Void)? = nil
    ) {
        self.date = date
        self.cells = cells
        self.calendar = calendar
        self.today = today
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeadline(date: date, calendar: calendar)

            WeekdayHeader(calendar: calendar, today: today, spacing: spacing)
                .padding(.top, 22)
                .padding(.bottom, 10)

            DotGrid(cells: cells, dotSize: nil, spacing: spacing, onTap: onTap)
        }
    }
}
```

Leave the doc comment above the struct (lines 90-92) in place.

- [ ] **Step 5: Run the package tests**

Run:
```bash
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test
```
Expected: all tests pass, including the new `onlyPaddingCellsLackADate`.

- [ ] **Step 6: Build the app to confirm the existing call site still compiles**

`PlanScreen.swift:96` calls `DotGrid(cells:dotSize:spacing:)` without `onTap`. Confirm it is unaffected:

```bash
xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/DotGrid.swift LifeOSKit/Sources/DesignSystem/MonthCalendarView.swift LifeOSKit/Tests/DesignSystemTests/MonthGridLayoutTests.swift
git commit -m "feat(design-system): let dots be tapped, and name them for VoiceOver

onTap defaults to nil, so the habit strips on the Plan tab are unchanged.
Padding cells and future days stay inert: neither has anything to open.
The grid had no accessibility labels at all before this."
```

---

## Task 4: `DayDetailSnapshot` and view-model selection

**Files:**
- Create: `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift`
- Modify: `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift`

**Interfaces:**
- Consumes: `PlanStore.tickedHabitIDs(on:) -> Set<UUID>` (Task 2); existing `MetricsStore.goals()`, `MetricsStore.metrics(from:to:)`, `PlanStore.entries(kind:)`, `PlanStore.toggleTick(for:on:)`.
- Produces:
  - `struct HabitRow: Identifiable, Equatable` with `let id: UUID`, `let title: String`, `let isDone: Bool`
  - `struct DayDetailSnapshot: Identifiable, Equatable` with `var id: Date { date }` and `date`, `isToday`, `steps: Int?`, `stepsTarget: Int`, `sleepMinutes: Int?`, `sleepTargetMinutes: Int`, `weightKg: Double?`, `recoveryPct: Double?`, `habits: [HabitRow]`
  - `TodayViewModel.detail: DayDetailSnapshot?` (private setter)
  - `TodayViewModel.select(_ date: Date)`, `.clearSelection()`, `.toggleHabit(id: UUID)`

  Tasks 5 and 6 depend on every name above.

- [ ] **Step 1: Create the snapshot type**

Create `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift`:

```swift
import Foundation

/// One habit as the day sheet renders it.
struct HabitRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isDone: Bool
}

/// Everything the day sheet renders, as plain values.
///
/// Same discipline as `TodaySnapshot`: the sheet never sees a `DailyMetrics` or
/// a `PlanEntry`, so rendering cannot fault a SwiftData object mid-layout.
///
/// `Identifiable` on the date is what drives `.sheet(item:)` — selecting a
/// different day while the sheet is open re-renders it rather than requiring a
/// dismiss first.
struct DayDetailSnapshot: Identifiable, Equatable {
    var id: Date { date }

    /// Always `Calendar.startOfDay`.
    let date: Date
    let isToday: Bool

    let steps: Int?
    let stepsTarget: Int
    let sleepMinutes: Int?
    let sleepTargetMinutes: Int
    let weightKg: Double?
    let recoveryPct: Double?

    /// Every habit that currently exists, done or not. Deliberately not
    /// filtered by creation date — see the spec's "Decision that shapes the
    /// sheet". The consequence is that an old day can list a habit that did not
    /// exist then, which is why the sheet's header is a count and never a grade.
    let habits: [HabitRow]
}
```

- [ ] **Step 2: Add selection to `TodayViewModel`**

In `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift`, add the `detail` property directly beneath the existing `snapshot` declaration on line 8:

```swift
    private(set) var snapshot = TodaySnapshot()
    /// The day the sheet is showing, or nil when it is closed.
    private(set) var detail: DayDetailSnapshot?
```

Then add these three methods after the closing brace of `load()` (line 78), still inside the class:

```swift
    /// Builds the day sheet's contents from both stores.
    ///
    /// A day with no metrics row is not an early return: its habits are still
    /// worth showing, and the metric rows render as blanks.
    func select(_ date: Date) {
        guard let context else { return }
        let metrics = MetricsStore(context: context, calendar: calendar)
        let plan = PlanStore(context: context, calendar: calendar)

        do {
            let day = calendar.startOfDay(for: date)
            let targets = try metrics.goals().targets
            let row = try metrics.metrics(from: day, to: day).first
            let ticked = try plan.tickedHabitIDs(on: day)

            detail = DayDetailSnapshot(
                date: day,
                isToday: calendar.isDateInToday(day),
                steps: row?.steps,
                stepsTarget: targets.steps,
                sleepMinutes: row?.sleepMinutes,
                sleepTargetMinutes: targets.sleepMinutes,
                weightKg: row?.weightKg,
                recoveryPct: row?.whoopRecoveryPct,
                habits: try plan.entries(kind: .habit).map { entry in
                    HabitRow(id: entry.id, title: entry.title, isDone: ticked.contains(entry.id))
                }
            )
        } catch {
            assertionFailure("Day detail load failed: \(error)")
        }
    }

    func clearSelection() {
        detail = nil
    }

    /// Only today can be ticked. Past days are history, and the sheet renders
    /// them without controls, so this guard is the second lock rather than the
    /// only one.
    func toggleHabit(id: UUID) {
        guard let context, let detail, detail.isToday else { return }

        do {
            let entry = try context.fetch(
                FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.id == id })
            ).first
            guard let entry else { return }

            try PlanStore(context: context, calendar: calendar)
                .toggleTick(for: entry, on: detail.date)

            // The month grid does not depend on habits, but reloading both
            // keeps one refresh path instead of two that can drift apart.
            load()
            select(detail.date)
        } catch {
            assertionFailure("Habit toggle failed: \(error)")
        }
    }
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: `** BUILD SUCCEEDED **`. Nothing calls the new methods yet — this step is checking that `Persistence` types resolve and the `#Predicate` compiles.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/Model/DayDetailSnapshot.swift LIfeOS/Features/Today/ViewModel/TodayViewModel.swift
git commit -m "feat(today): build a day-detail snapshot from metrics and habits

Today owned MetricsStore already; it picks up PlanStore beside it so a
single day can be described in one value. Habits do not feed evaluate(),
so dot colours are unchanged."
```

---

## Task 5: `DayDetailSheet`

**Files:**
- Create: `LIfeOS/Features/Today/View/DayDetailSheet.swift`

**Interfaces:**
- Consumes: `DayDetailSnapshot`, `HabitRow` (Task 4); `SolidCard` and `LifeOSTokens` from `DesignSystem`; `TodayScreen.duration(_:)`, the existing static helper at `TodayScreen.swift:71`.
- Produces: `struct DayDetailSheet: View` with `init(snapshot: DayDetailSnapshot, onToggleHabit: @escaping (UUID) -> Void)` — the memberwise init, used by Task 6.

- [ ] **Step 1: Create the sheet**

Create `LIfeOS/Features/Today/View/DayDetailSheet.swift`:

```swift
import SwiftUI
import DesignSystem

/// One day in full: what the metrics said, and which habits were done.
///
/// Past days are history and render as static marks. Only today gets controls,
/// so the grid can never be rewritten after the fact.
struct DayDetailSheet: View {
    let snapshot: DayDetailSnapshot
    let onToggleHabit: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    metrics
                    habits
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
            .navigationTitle(snapshot.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var metrics: some View {
        SolidCard {
            VStack(spacing: 0) {
                MetricRow(
                    label: "Steps",
                    value: snapshot.steps.map { $0.formatted() },
                    detail: "of \(snapshot.stepsTarget.formatted())"
                )
                Divider()
                MetricRow(
                    label: "Sleep",
                    value: snapshot.sleepMinutes.map(TodayScreen.duration),
                    detail: "of \(TodayScreen.duration(snapshot.sleepTargetMinutes))"
                )
                Divider()
                MetricRow(
                    label: "Weight",
                    value: snapshot.weightKg.map { String(format: "%.1f kg", $0) }
                )
                Divider()
                MetricRow(
                    label: "Recovery",
                    value: snapshot.recoveryPct.map { "\(Int($0))%" }
                )
            }
        }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A bare count, never a percentage or a grade. This list includes
            // habits that may not have existed on an older day, so it must not
            // read as a verdict on that day.
            Text("\(snapshot.habits.filter(\.isDone).count) of \(snapshot.habits.count) habits")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

            if snapshot.habits.isEmpty {
                Text("No habits yet. Add one on the Plan tab.")
                    .font(.system(size: 15))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            } else {
                SolidCard {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.habits.enumerated()), id: \.element.id) { index, habit in
                            if index > 0 { Divider() }
                            habitRow(habit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func habitRow(_ habit: HabitRow) -> some View {
        if snapshot.isToday {
            Button { onToggleHabit(habit.id) } label: { habitLabel(habit) }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    habit.isDone
                        ? "\(habit.title), done. Mark not done"
                        : "\(habit.title), not done. Mark done"
                )
        } else {
            habitLabel(habit)
                .accessibilityLabel("\(habit.title), \(habit.isDone ? "done" : "not done")")
        }
    }

    private func habitLabel(_ habit: HabitRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: habit))
                .font(.system(size: snapshot.isToday ? 22 : 16, weight: .semibold))
                .foregroundStyle(
                    habit.isDone
                        ? LifeOSTokens.accent
                        : LifeOSTokens.secondaryText.resolve(scheme)
                )
                .frame(width: 24)

            Text(habit.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
    }

    /// Today gets the tappable circle vocabulary used on the Plan tab. A past
    /// day gets a plain mark, because there is nothing there to press.
    private func icon(for habit: HabitRow) -> String {
        if snapshot.isToday {
            habit.isDone ? "checkmark.circle.fill" : "circle"
        } else {
            habit.isDone ? "checkmark" : "xmark"
        }
    }
}

/// One metric line. A missing value renders as an em dash rather than hiding the
/// row, so the sheet's height does not jump as you move between days.
private struct MetricRow: View {
    let label: String
    let value: String?
    var detail: String? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            Spacer()

            Text(value ?? "—")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))

            // The target is context for a number. With no number it is noise.
            if let detail, value != nil {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(.vertical, 12)
    }
}

private let previewHabits = [
    HabitRow(id: UUID(), title: "Read 20 min", isDone: true),
    HabitRow(id: UUID(), title: "Gym", isDone: true),
    HabitRow(id: UUID(), title: "Water 2.5L", isDone: false),
    HabitRow(id: UUID(), title: "Journal", isDone: false),
]

#Preview("Today") {
    DayDetailSheet(
        snapshot: DayDetailSnapshot(
            date: Calendar.current.startOfDay(for: .now),
            isToday: true,
            steps: 3102, stepsTarget: 8000,
            sleepMinutes: 440, sleepTargetMinutes: 420,
            weightKg: 77.4, recoveryPct: 62,
            habits: previewHabits
        ),
        onToggleHabit: { _ in }
    )
}

#Preview("Past day, partial data") {
    DayDetailSheet(
        snapshot: DayDetailSnapshot(
            date: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
            isToday: false,
            steps: 6204, stepsTarget: 8000,
            sleepMinutes: nil, sleepTargetMinutes: 420,
            weightKg: nil, recoveryPct: nil,
            habits: previewHabits
        ),
        onToggleHabit: { _ in }
    )
}
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Check both previews in Xcode**

Open `DayDetailSheet.swift` in Xcode and run the canvas. Confirm against the spec:
- "Today" preview: four metric rows, habit rows show filled/empty circles and are pressable.
- "Past day" preview: Sleep, Weight and Recovery read `—` with no target text beside them; habit rows show ✓/✗ and do not respond to taps.
- Both previews: the habit header reads `2 of 4 habits` — no percentage, no grade.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/View/DayDetailSheet.swift
git commit -m "feat(today): add the day-detail sheet

Metrics are read-only everywhere. Habits are tappable on today and static
marks on any past day. The habit header is a count, never a grade: the
list includes habits that may not have existed on an older day."
```

---

## Task 6: Wire the grid to the sheet

**Files:**
- Modify: `LIfeOS/Features/Today/View/TodayScreen.swift:4-18` and the `#Preview` at `:76-87`
- Modify: `LIfeOS/App/RootView.swift` (Today tab body, and the sheet stack)

**Interfaces:**
- Consumes: `MonthCalendarView.init(date:cells:calendar:today:onTap:)` (Task 3); `TodayViewModel.detail`/`.select(_:)`/`.clearSelection()`/`.toggleHabit(id:)` (Task 4); `DayDetailSheet.init(snapshot:onToggleHabit:)` (Task 5); `AppTab` and the bound `TabView` (Task 1).
- Produces: `TodayScreen.init(snapshot:onSelectDay:)` where `onSelectDay: (Date) -> Void`. This is the last task; nothing consumes it.

- [ ] **Step 1: Give `TodayScreen` a selection callback**

In `LIfeOS/Features/Today/View/TodayScreen.swift`, replace lines 4-18 (the property list and the `MonthCalendarView` call) with:

```swift
struct TodayScreen: View {
    let snapshot: TodaySnapshot
    /// Raised when a dot for a real, non-future day is tapped. The screen stays
    /// a pure function of its inputs: it does not decide what a day opens.
    let onSelectDay: (Date) -> Void

    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MonthCalendarView(
                    date: snapshot.date,
                    cells: snapshot.cells,
                    calendar: calendar,
                    today: snapshot.date,
                    onTap: { cell in
                        // `DotGrid` only calls this for tappable cells, which
                        // always carry a date. The guard is belt and braces.
                        if let date = cell.date { onSelectDay(date) }
                    }
                )
```

Everything from `streakLine` onward is unchanged.

- [ ] **Step 2: Update the `TodayScreen` preview**

At the bottom of the same file, the `#Preview` constructs `TodayScreen(snapshot:)` and will no longer compile. Replace the entire existing `#Preview` block with this. Argument order must match the declaration — `snapshot` first, then `onSelectDay`:

```swift
#Preview {
    TodayScreen(
        snapshot: TodaySnapshot(
            cells: (0..<35).map { DotCell(id: $0, date: nil, state: $0 < 10 ? .onTarget : ($0 == 10 ? .today : .future)) },
            streak: 6,
            steps: 8432,
            stepsProgress: 1.05,
            sleepMinutes: 432,
            sleepProgress: 0.9,
            weightKg: 77.4,
            recoveryPct: nil
        ),
        onSelectDay: { _ in }
    )
}
```

- [ ] **Step 3: Pass the callback from `RootView`**

In `LIfeOS/App/RootView.swift`, inside the Today tab, change:

```swift
                        TodayScreen(snapshot: today.snapshot)
```

to:

```swift
                        TodayScreen(snapshot: today.snapshot, onSelectDay: { today.select($0) })
```

The `.toolbar` modifier chained after it is unchanged.

- [ ] **Step 4: Present the sheet**

In `LIfeOS/App/RootView.swift`, add this alongside the other `.sheet` modifiers — put it first, immediately after the closing brace of the `ZStack` and before `.sheet(isPresented: $showQuickLog)`:

```swift
        // `today.detail` is the only source of truth for what the sheet shows;
        // there is deliberately no parallel `selectedDay` state to keep in step.
        .sheet(item: Binding(
            get: { today.detail },
            set: { if $0 == nil { today.clearSelection() } }
        )) { detail in
            DayDetailSheet(snapshot: detail) { today.toggleHabit(id: $0) }
        }
```

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Run the full package suite**

Run:
```bash
cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test
```
Expected: all tests pass.

- [ ] **Step 7: Verify the whole feature in the simulator**

Launch the app and walk the spec:

1. App opens on Today.
2. Tap a past dot → the sheet opens for that day. Metrics show values or `—`. Habits show ✓/✗ and do not respond to taps.
3. Tap today's dot (the accent-coloured one) → habit rows show circles. Tap one; it fills. Dismiss the sheet, reopen today's dot — the tick persisted.
4. Switch to the Plan tab → the habit you ticked shows as done there too.
5. Tap a future (pale) dot → nothing happens.
6. Tap a padding cell before the 1st → nothing happens.
7. Turn on VoiceOver and swipe across the grid → dots announce as e.g. "5 August, on target"; padding cells are skipped.
8. Add a brand-new habit on the Plan tab, then open a dot from earlier in the month → it appears there marked not done, and the header reads a count like `2 of 5 habits`. This is the accepted consequence of the spec's decision, not a bug.

- [ ] **Step 8: Commit**

```bash
git add LIfeOS/Features/Today/View/TodayScreen.swift LIfeOS/App/RootView.swift
git commit -m "feat(today): open a day's detail by tapping its dot

The month grid was the densest thing on the screen and the only one you
could not interrogate. today.detail is the single source of truth for the
sheet, so there is no selected-day state to keep in step with it."
```

---

## Verification Checklist

Run before considering the plan complete:

- [ ] `cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test` — all suites pass
- [ ] `xcodebuild -project /Users/shivvyas/LIfeOS/LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build` — succeeds
- [ ] The two non-goals held. Both files are new on `feat/v1-foundation`, so this must be diffed against where *this plan* started, not against `main`. Capture the baseline before Task 1:

  ```bash
  cd /Users/shivvyas/LIfeOS && git rev-parse --short HEAD > /tmp/lifeos-plan-baseline
  ```

  and check it at the end:

  ```bash
  cd /Users/shivvyas/LIfeOS && git diff "$(cat /tmp/lifeos-plan-baseline)" --stat -- \
    LifeOSKit/Sources/Persistence/GoalEvaluation.swift \
    LIfeOS/Features/Plan/View/PlanScreen.swift
  ```

  Expected: no output. `GoalEvaluation.swift` unchanged means dot colours still mean what they did; `PlanScreen.swift` unchanged means the `onTap` default of `nil` genuinely left the Plan tab's dot strips alone.
- [ ] Task 6 Step 7's eight simulator checks all pass
