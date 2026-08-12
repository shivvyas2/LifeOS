# Whoop data display and responsive layout

**Date:** 2026-08-11
**Status:** Approved

## Problem

Two problems, one pass.

**Whoop data is synced and mostly discarded.** `WhoopSync.sync()` pulls fourteen
days of recoveries, sleeps and cycles on every run and writes six fields to the
daily spine. Every screen then renders a single day. `whoopSleepPerformancePct`
is written by `WhoopIngestion.swift:54` and read nowhere at all. Recovery is
shown as a bare number with no colour language, so 31% and 81% look alike.
Nothing reports when the last sync happened, which makes a dead connection
indistinguishable from a quiet week.

**The app has no responsive layout of any kind.** `TARGETED_DEVICE_FAMILY` is
already `"1,2"`, so it installs on iPad today, but the codebase contains no
`horizontalSizeClass`, no `GeometryReader` and no adaptive `GridItem`. Padding
is hardcoded at 20/24pt, grids are fixed at two columns, tile rows are
three-element `HStack`s, and type is set in fixed points. On a 13" iPad that is
a phone layout stretched across 1366pt. It is also moot until orientation is
unlocked: `project.pbxproj:292` and `:326` pin every configuration to
`UIInterfaceOrientationPortrait`.

## Goals

- Show the Whoop data that is already being synced: today in full, and the
  fourteen-day trend behind it.
- Make every screen adapt from iPhone portrait to iPad landscape, with an
  iPad-native sidebar rather than a stretched tab bar.

## Non-goals

- iPhone landscape. Compact-height needs its own treatment for the month grid
  and hero numerals; this pass unlocks landscape on iPad only.
- New Whoop API surface. Workouts, sleep stages and cycle detail are not
  fetched today and are not added here.
- Changing what is synced or how often.

## Constraint that shapes the architecture

`Tokens.swift:44` records that LifeOSKit builds for macOS so that `swift test`
runs from the terminal without a simulator. `horizontalSizeClass` is UIKit-only.
Any layout logic placed in the design system must therefore be expressed over a
platform-free type, with the UIKit read confined to a single shim in the app
target. Violating this trades fast terminal tests for a simulator boot on every
run.

## Design

### 1. Layout foundation

New `LifeOSKit/Sources/DesignSystem/LayoutMetrics.swift`:

```swift
public enum LayoutWidth: Sendable { case compact, regular }

public struct LayoutMetrics: Sendable, Equatable {
    public let gutter: CGFloat           // 20 → 32
    public let sectionSpacing: CGFloat   // 22 → 30
    public let maxContentWidth: CGFloat  // .infinity → 860
    public let heroScale: CGFloat        // 1.0 → 1.3, applied by HeroNumeral
    public let fabBottomInset: CGFloat   // 72 → 28

    public static func metrics(for width: LayoutWidth) -> LayoutMetrics

    /// Column count from real available width.
    public static func columns(availableWidth: CGFloat,
                               minimum: CGFloat,
                               maximum: Int) -> Int
}
```

`LayoutWidth` is our own enum rather than `UserInterfaceSizeClass` so the type
and its metrics compile and test on macOS.

`columns(availableWidth:minimum:maximum:)` is the load-bearing function: it is
what keeps a 4-up grid on a 13" iPad from becoming a 7-up grid of postage
stamps. Every adaptive grid in the app calls it.

`maxContentWidth` caps prose and single-column content so a 1366pt pane does not
produce 90-character measures. Grids are exempt and fill the pane, which is why
the approved iPad layout has no dead margins.

Exposed as an environment value:

```swift
extension EnvironmentValues { public var layout: LayoutMetrics { get set } }
```

defaulting to compact. The app target injects it once, at the shell:

```swift
#if canImport(UIKit)
@Environment(\.horizontalSizeClass) private var sizeClass
// .regular → LayoutWidth.regular, else .compact
#endif
```

Views read `@Environment(\.layout)` and use `layout.gutter` in place of
hardcoded numbers. This mirrors the existing `Space` enum, so it reads as part
of the design system rather than bolted onto it.

### 2. Recovery colour language

New `LifeOSKit/Sources/DesignSystem/RecoveryBand.swift`:

```swift
public enum RecoveryBand: Sendable, Equatable {
    case low, moderate, high          // <34 · 34-66 · ≥67
    public static func band(for percentage: Double) -> RecoveryBand
    public var color: Color           // red · amber · green
    public var label: String          // "Low" · "Moderate" · "High"
}
```

Whoop's own thresholds, so the app agrees with the Whoop app about what a number
means. Boundaries (33/34, 66/67) are tested, because an off-by-one in a band is
invisible until it is wrong on screen.

### 3. Trend roll-up

New `LifeOSKit/Sources/DesignSystem/TrendSeries.swift`:

```swift
public struct TrendPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Double?     // nil is a gap, never a zero
}

public struct TrendSeries: Sendable, Equatable {
    public let points: [TrendPoint]
    public var average: Double?          // over non-nil values only
    public var latest: Double?
    public var deltaFromAverage: Double?
}
```

Pure over plain values: no SwiftData, no SwiftUI, so it tests on macOS. The
existing rule that a missing value and a zero are different things (`DailyMetrics`
header) carries through: a gap renders as a gap in the chart, never a bar of
height zero.

`RecoveryViewModel` gains a fourteen-day fetch via the existing
`MetricsStore.metrics(from:to:)` and builds six series: recovery, day strain,
sleep minutes, sleep performance percentage, HRV and resting heart rate.
`RecoverySnapshot` grows the series plus `syncedAt`.

### 4. Whoop UI

New views under `LIfeOS/Features/Recovery/View/`:

| View | Role |
| --- | --- |
| `WhoopDayCard` | Recovery percentage in its band colour, then sleep performance, HRV, resting HR and day strain. Shows a chevron only in compact width. |
| `WhoopTrendsContent` | Six Swift Charts bar series over fourteen days, today highlighted, dashed rule at the average. |
| `WhoopDetailScreen` | Wrapper hosting `WhoopTrendsContent` when pushed. |

Presentation differs by width, content does not:

- **Compact**: the card is a `NavigationLink` pushing `WhoopDetailScreen`.
- **Regular**: card and trends render side by side inside the Recovery
  section, with no push.

`RecoverySection` also renders "Synced 2h ago" from `syncedAt`, so a dead
connection is visible rather than silent.

Swift Charts is used rather than hand-rolled bars: the deployment target is
iOS 26, and axis handling, gaps and accessibility come free.

### 5. Shell and orientation

In `RootView.swift`:

- `.tabViewStyle(.sidebarAdaptable)` on the `TabView`: sidebar in regular
  width, tab bar on iPhone.
- The Body tab gains a `NavigationStack`; it has none today, so the Recovery
  push has nowhere to go without one.
- The quick-log FAB takes its bottom inset from `layout.fabBottomInset`, so it
  stops floating 72pt above a tab bar that is not there.

In `project.pbxproj`, both configurations gain
`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` with all four
orientations. The existing iPhone key stays portrait-only.

### 6. Per-screen application

| Screen | Change |
| --- | --- |
| `TodayScreen` | Month calendar capped and centred; stat grid adapts 2-up → 4-up |
| `BodyHubScreen` | Week strip and segmented pill widen to the pane; section content is capped and centred |
| `RecoverySection` | Rebuilt per §4. The only section that goes two-pane in regular width |
| `ActivitySection`, `WeightSection`, `WellnessSection` | Three-tile `HStack` → adaptive grid; journal list capped |
| `MoneyScreen` | Adaptive grid; transaction rows capped |
| `PlanScreen`, `ContentCalendar` | Adaptive grid; calendar given real width |
| `SettingsScreen` | `.presentationSizing(.form)` in regular width |
| `IntroScreen`, `SignupScreens`, `ConnectionsScreen` | Centred readable column |
| `AddEntrySheet`, `JournalEntrySheet`, `QuickLogSheet`, `AddMoneySheet` | `.presentationSizing(.form)` |

## Testing

Unit tests in LifeOSKit, run by `swift test` with no simulator:

- `LayoutMetricsTests`: column count against width and minimum, including the
  maximum cap and a width narrower than one minimum tile; regular metrics differ
  from compact.
- `RecoveryBandTests`: the 33/34 and 66/67 boundaries, and the 0 and 100 ends.
- `TrendSeriesTests`: average ignores gaps; an all-gap series has a nil average
  rather than a zero; `deltaFromAverage` sign and nil handling.

Manual verification, because a responsive claim cannot be checked any other way:
build and launch on iPhone 17 Pro and iPad Pro 13" in landscape, and capture
Today, Body › Recovery, Money and Plan on both.

## Risks

- **`.sidebarAdaptable` changes navigation on iPad.** It is one modifier, but it
  restructures how the four tabs present. Verified by screenshot, not assumed.
- **Six charts may be too dense** on a phone. If the detail screen reads as
  noise, cut to recovery, strain and sleep; the other three are already in the
  day card as numbers.
- **`presentationSizing` on regular width** changes sheet dimensions across the
  app at once; each sheet needs a look, not just a compile.
