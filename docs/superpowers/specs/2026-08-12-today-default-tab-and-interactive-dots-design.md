# Today as the default tab, and dots you can tap

**Date:** 2026-08-12
**Status:** Approved

## Problem

Two problems, one pass. Both are about Today being the app's home surface and
not quite behaving like one.

**The default tab is implicit, and the route to it is not persisted.**
`RootView.swift:39` builds a bare `TabView` with no selection binding, so
"Today opens first" is a consequence of `Tab("Today", …)` happening to be
written first rather than a decision the code states. In practice the app has
been observed opening on another tab. Separately, `AppShell.swift:15-19` keeps
`hasFinishedOnboarding` in plain `@State`, so a returning, already-signed-in
user sees the intro carousel flash for a frame before `.task` catches up and
skips it — `isSignedIn` resolves synchronously but `@State` starts false on
every launch. (This has no effect on a relaunch that cannot restore a session;
that always re-runs onboarding, with or without this flag.)

**The month grid is a picture, not an interface.** `MonthCalendarView` renders
one dot per day, coloured by `evaluate()` in `GoalEvaluation.swift:52`. Tapping
a dot does nothing, so the single densest object on the screen — thirty-odd days
of history — is unreadable in detail. There is no way to ask "what actually
happened on the 5th?".

Habits compound this. `PlanEntry(kind: .habit)` and `HabitTick` already record a
full history, and `PlanScreen.swift:96` renders it with the same dot vocabulary,
but Today never reads either. The two halves of the same day live on two tabs
that do not know about each other.

## Goals

- Make Today the default tab by construction, not by ordering accident, and keep
  a returning user out of onboarding.
- Make a day's dot open that day: its metrics and its habits, in one sheet.
- Let today's habits be ticked from that sheet, so logging does not require a
  trip to the Plan tab.

## Non-goals

- **Habits do not change dot colour.** `evaluate()` is untouched. A dot's fill
  stays a function of steps, sleep, exercise and water. Habits appear inside the
  sheet only. Folding habits into the day status is a real idea, but it
  rewrites the meaning of every dot already on screen and belongs in its own
  pass.
- **No backfilling.** Past days are read-only. Only today's habits can be
  toggled.
- **No new schema.** `PlanEntry`, `HabitTick` and `DailyMetrics` are unchanged.
- Editing metrics from the sheet. Steps and sleep come from Whoop and the
  quick-log sheet; the day detail does not become a second writer.

## Decision that shapes the sheet

A past day's sheet lists **all habits that currently exist**, marking un-ticked
ones as not done.

The honest alternative is to filter by `PlanEntry.createdAt`, so a habit added
yesterday does not appear on last week's days. It was considered and rejected as
too clever for the value: the denominator would shift as you scroll back through
the month, which is harder to read than a stable list.

The cost is real and must be contained: a day before a habit existed will show
that habit as not done. The containment is in the copy. The header reads
`2 of 4 habits`, never a percentage, grade, or "missed" — a count of what was
done, not a verdict on the day. `DotState.missed` language stays out of the
habit section entirely.

## Design

### 1. Deterministic tab selection

`RootView` gains an explicit tab identity:

```swift
private enum AppTab: Hashable { case today, body, money, plan }

@State private var tab: AppTab = .today
```

`TabView(selection: $tab)`, and each `Tab` gains `value:`. The default tab is
now a stated initial value. `tab` is deliberately *not* persisted to
`@SceneStorage` or `@AppStorage`: the requirement is that a cold launch lands on
Today, and non-persisted `@State` delivers that for free. Selection still
survives backgrounding, because the scene stays alive.

`AppShell` moves `hasFinishedOnboarding` to `@AppStorage("hasFinishedOnboarding")`
so a returning, already-signed-in user does not see the intro carousel flash
before `.task` catches up. It does not change what happens when the session
cannot be restored.

`isGuest` stays non-persisted. `AppShell.swift:16` explains why — the "Skip for
now" bypass must not quietly become the app's default state — and that reasoning
is unaffected by this change.

### 2. `DotGrid` becomes optionally interactive

`LifeOSKit/Sources/DesignSystem/DotGrid.swift`:

```swift
public init(
    cells: [DotCell],
    dotSize: CGFloat? = 22,
    spacing: CGFloat = 8,
    onTap: ((DotCell) -> Void)? = nil
)
```

Default `nil` keeps `PlanScreen.swift:96` — the only other call site — compiling
and behaving identically.

A cell is tappable when `onTap != nil`, `cell.date != nil`, and its state is not
`.future` or `.blank`. Tappable cells are wrapped in a `Button` with
`.buttonStyle(.plain)`; everything else renders exactly as it does now. Future
and padding days have nothing to show, so they stay inert rather than opening an
empty sheet.

Every cell with a date gains an accessibility label regardless of tappability —
`"5 August, on target"` — which the grid does not have at all today.
`MonthCalendarView` forwards an `onTap` parameter through to the grid.

### 3. Day detail data

New `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift`, following the plain-values
discipline of `TodaySnapshot` — the sheet never sees a SwiftData object:

```swift
struct HabitRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isDone: Bool
}

struct DayDetailSnapshot: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let isToday: Bool
    let steps: Int?
    let stepsTarget: Int
    let sleepMinutes: Int?
    let sleepTargetMinutes: Int
    let weightKg: Double?
    let recoveryPct: Double?
    let habits: [HabitRow]
}
```

`Identifiable` on `date` is what drives `.sheet(item:)`, so selecting a
different day while the sheet is open re-renders it rather than needing a
dismiss.

### 4. `PlanStore.tickedHabitIDs(on:)`

```swift
public func tickedHabitIDs(on date: Date) throws -> Set<UUID>
```

One fetch of `HabitTick` for `calendar.startOfDay(for: date)`, returning the
entry IDs. The existing `recentTicks(for:days:endingOn:)` is per-entry, so
building a day's rows through it would be one fetch per habit.

### 5. `TodayViewModel` gains selection

`TodayViewModel` already owns `MetricsStore`; it picks up `PlanStore` beside it.

```swift
private(set) var detail: DayDetailSnapshot?

func select(_ date: Date)      // builds and assigns `detail`
func clearSelection()
func toggleHabit(id: UUID)     // today only; writes, then reloads
```

`select` reads the day's `DailyMetrics` row, the goal targets, all
`PlanKind.habit` entries, and `tickedHabitIDs(on:)`, and assembles the snapshot.
A day with no metrics row yields nil metric fields and a full habit list — the
sheet is still worth opening.

`toggleHabit` guards on `detail?.isToday == true`, calls
`PlanStore.toggleTick`, then re-runs both `load()` and `select(detail.date)`.
The month grid is unaffected by a habit tick today, since habits do not feed
`evaluate()`, but `load()` is cheap and keeps one refresh path rather than two.

Read failures follow the existing convention at `TodayViewModel.swift:76`:
`assertionFailure` and leave the previous value in place, rather than blanking
the screen for something the user cannot act on.

### 6. `DayDetailSheet`

New `LIfeOS/Features/Today/View/DayDetailSheet.swift`. Takes a
`DayDetailSnapshot` and an `onToggleHabit: (UUID) -> Void`.

- Header: the day's date, formatted long.
- Metrics: rows for steps (with target), sleep (with target), weight and
  recovery. Rows with no value read `—` rather than being hidden, so the sheet's
  height does not jump between days.
- Habits: header `"\(doneCount) of \(habits.count) habits"`. When `isToday`,
  each row is a tappable button with a filled/empty circle, matching the control
  vocabulary at `PlanScreen.swift:100-107`. When not, each row is a static ✓/✗.

`today.detail` is the single source of truth for what the sheet shows; `RootView`
holds no parallel `selectedDay` state. It passes `onSelectDay: { today.select($0) }`
into `TodayScreen` and presents with:

```swift
.sheet(item: Binding(
    get: { today.detail },
    set: { if $0 == nil { today.clearSelection() } }
))
```

Dismissing sets the binding to nil, which clears the view model's selection.

`TodayScreen` gains an `onSelectDay: (Date) -> Void` parameter and forwards it
into `MonthCalendarView`. It stays a pure function of its inputs.

## Testing

Design-system and persistence tests run under `swift test` from the terminal
without a simulator; that constraint is unchanged here.

- `PlanStoreTests.tickedHabitIDs(on:)`: returns only that day's entry IDs;
  returns empty for a day with no ticks; a tick at 23:59 local belongs to that
  day and not the next (the `startOfDay` boundary).
- `MonthGridLayoutTests`: assert every `.blank` cell has a nil `date`, and every
  cell for a real day has a non-nil one. That nil now gates whether a dot is
  tappable, so it has become load-bearing rather than cosmetic.
- `DotGrid` previews gain an interactive variant, so the tap affordance is
  visible without booting the app.

Sheet layout and the tab default are verified by running the app.

## Files

Changed:

- `LIfeOS/App/RootView.swift` — `AppTab`, selection binding, sheet presentation
- `LIfeOS/App/AppShell.swift` — `@AppStorage` for `hasFinishedOnboarding`
- `LIfeOS/Features/Today/View/TodayScreen.swift` — `onSelectDay` parameter
- `LIfeOS/Features/Today/ViewModel/TodayViewModel.swift` — `PlanStore`, `detail`,
  `select`, `clearSelection`, `toggleHabit`
- `LifeOSKit/Sources/DesignSystem/DotGrid.swift` — `onTap`, accessibility labels
- `LifeOSKit/Sources/DesignSystem/MonthCalendarView.swift` — forwards `onTap`
- `LifeOSKit/Sources/Persistence/PlanStore.swift` — `tickedHabitIDs(on:)`

Added:

- `LIfeOS/Features/Today/Model/DayDetailSnapshot.swift`
- `LIfeOS/Features/Today/View/DayDetailSheet.swift`

Unchanged, deliberately: `GoalEvaluation.swift`, `PlanEntry.swift`,
`DailyMetrics.swift`, `PlanScreen.swift`.
