# Health Restructure + App-Wide Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Body tab to Health with two segments (Health | Fitness), add baseline-deviation anomaly alerts, and restyle the whole app from saturated gradient canvases to a soft light-card aesthetic with a custom floating pill nav.

**Architecture:** All visual change happens in-place in the `LifeOSKit` `DesignSystem` package so every tab flips together. Anomaly math is pure functions in `Persistence` (unit-tested via `swift test`). The app target regroups existing snapshot-pure sections into two new segment views; no schema, sync, or persistence changes.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), local SPM package `LifeOSKit` (targets `DesignSystem`, `Persistence`, `Integrations` — builds for macOS 26 so tests run terminal-side), SwiftData, Swift Testing (`@Test`/`#expect`) in package tests.

**Spec:** `docs/superpowers/specs/2026-08-25-health-restructure-restyle-design.md`

## Global Constraints

- The `LifeOSKit` package must keep building for macOS 26: no UIKit-only APIs in the package; colors are explicit `AdaptiveColor` light/dark pairs resolved via `@Environment(\.colorScheme)`, never `Color(.systemBackground)`.
- Missing data renders as "—" or an absent view, never zero ("a false zero is worse than a blank").
- Views are pure functions of `Equatable` snapshot structs; `@MainActor @Observable` view models own the `ModelContext`; `RootView` is the single composition root.
- Dark mode fully supported: every new/changed color is an `AdaptiveColor` pair.
- Anomaly banner wording is descriptive ("well above your baseline"), never diagnostic or prescriptive — no "contact doctor".
- Commit messages: NO `Co-Authored-By` trailer (user preference).
- Package tests: `cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test`
- App build check: `cd /Users/shivvyas/LIfeOS && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build` (append `2>&1 | tail -20` to keep output readable; expect `** BUILD SUCCEEDED **`).
- SwiftUI view components in `DesignSystem` have no meaningful unit surface; they are verified by package build + `#Preview` + the app build. Pure logic (anomaly math) is TDD'd.

## File Structure (end state)

```
LifeOSKit/Sources/DesignSystem/
  Tokens.swift            MODIFIED: pastel hues, accentSoft, alert colors; tileSurface revalued; onGradient DELETED
  GradientCanvas.swift    MODIFIED: flat canvas + subtle pastel tint wash
  GlassCard.swift         REWRITTEN: single SoftCard (GlassCard + SolidCard deleted); file renamed SoftCard.swift
  MetricTile.swift        MODIFIED: MetricTile + SegmentedPill restyled for light canvas
  WeekStrip.swift         REWRITTEN: ring-progress day cells
  PillNavBar.swift        NEW: floating pill tab bar
  IconBubbleTile.swift    NEW: pastel icon bubble + big number card content
  RoundedBarChart.swift   NEW: two-tone rounded weekly bars
  AlertBanner.swift       NEW: red alert card
  DotBloom.swift          MODIFIED: onGradient call sites replaced
LifeOSKit/Sources/Persistence/
  AnomalyEvaluation.swift NEW: baselines + thresholds + findings (pure)
LifeOSKit/Tests/PersistenceTests/
  AnomalyEvaluationTests.swift NEW
LIfeOS/Features/Health/               NEW GROUP (replaces Features/Body)
  Model/HealthSection.swift           NEW (BodySection.swift DELETED)
  View/HealthHubScreen.swift          NEW (BodyHubScreen.swift DELETED)
  View/HealthSegmentView.swift        NEW (absorbs RecoverySection + journal card)
  View/FitnessSegmentView.swift       NEW (absorbs ActivitySection + weekly rollup; owns WorkoutRow)
  View/StatGroup.swift                NEW (moved out of RecoveryScreen.swift)
LIfeOS/Features/Body/View/BodyScreen.swift      MODIFIED: WeightSection restyled (kept, rendered inside Health segment)
LIfeOS/Features/Body/View/WellnessSection.swift DELETED (journal card → HealthSegmentView, rollup → FitnessSegmentView)
LIfeOS/Features/Activity/View/ActivityScreen.swift DELETED (WorkoutRow → FitnessSegmentView.swift)
LIfeOS/Features/Recovery/View/RecoveryScreen.swift DELETED (StatGroup → Features/Health/View/StatGroup.swift)
LIfeOS/Features/Recovery/View/WhoopDetailScreen.swift MODIFIED: restyle-only fixes
LIfeOS/Features/Recovery/Model/RecoverySnapshot.swift MODIFIED: + anomalies
LIfeOS/Features/Recovery/ViewModel/RecoveryViewModel.swift MODIFIED: computes anomalies
LIfeOS/Features/Activity/Model/ActivitySnapshot.swift MODIFIED: + weekCalories
LIfeOS/Features/Activity/ViewModel/ActivityViewModel.swift MODIFIED: fetches week window
LIfeOS/App/RootView.swift             MODIFIED: PillNavBar replaces TabView chrome; Health wiring
Money/Plan/Today/Onboarding screens   MODIFIED: mechanical token migration
```

**View-model decision (spec §6):** the four existing view models (`ActivityViewModel`, `BodyViewModel`, `RecoveryViewModel`, `WellnessViewModel`) are KEPT — the spec makes snapshot purity the invariant, not file layout. No `HealthViewModel` is created. `HealthHubScreen` receives the same four snapshots `BodyHubScreen` received.

**Week-strip ring decision:** each day's ring shows that day's Whoop recovery % (0–1 trim). Recovery is already fetched for the 14-day window by `RecoveryViewModel`, needs no new goal plumbing, and is the natural "how did that day go" signal for the Health tab. Days without recovery show an empty ring track.

---

### Task 1: Design tokens — pastels, accentSoft, alert colors

Additive only; nothing breaks. `onGradient` deletion happens in Task 6.

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/Tokens.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/TokensTests.swift`

**Interfaces:**
- Produces: `ModuleHue.pastel: Color`, `ModuleHue.pastelDark: Color`, `LifeOSTokens.accentSoft: AdaptiveColor`, `LifeOSTokens.alertBackground: AdaptiveColor`, `LifeOSTokens.alertText: AdaptiveColor`, `LifeOSTokens.cardShadow: Color` — used by Tasks 3–6.

- [ ] **Step 1: Read `LifeOSKit/Tests/DesignSystemTests/TokensTests.swift`** to match its existing test style (Swift Testing vs XCTest) exactly.

- [ ] **Step 2: Add a failing test** in that file, in the file's existing style. Content to assert (adapt syntax to match the file):

```swift
@Test func pastelHuesAreDefinedAndDistinctFromSaturated() {
    for hue in ModuleHue.allCases {
        #expect(hue.pastel != hue.top)
        #expect(hue.pastelDark != hue.darkTop)
    }
}

@Test func alertColorsDifferByScheme() {
    #expect(LifeOSTokens.alertBackground.resolve(.light) != LifeOSTokens.alertBackground.resolve(.dark))
    #expect(LifeOSTokens.alertText.resolve(.light) != LifeOSTokens.alertText.resolve(.dark))
}
```

- [ ] **Step 3: Run to verify failure**: `cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test --filter TokensTests`. Expected: compile error "value of type 'ModuleHue' has no member 'pastel'".

- [ ] **Step 4: Implement.** In `Tokens.swift`, add to `ModuleHue` (after `darkBottom`):

```swift
    /// Soft tint of the hue for icon bubbles, chart fills and canvas washes.
    /// The saturated `top` colours survive only as chart/accent ink; pastel
    /// carries the module identity on the light canvas.
    public var pastel: Color {
        switch self {
        case .body:      Color(red: 0.84, green: 0.92, blue: 0.90)
        case .activity:  Color(red: 0.98, green: 0.89, blue: 0.78)
        case .recovery:  Color(red: 0.85, green: 0.90, blue: 0.98)
        case .nutrition: Color(red: 0.90, green: 0.87, blue: 0.98)
        case .money:     Color(red: 0.85, green: 0.93, blue: 0.87)
        case .habits:    Color(red: 0.99, green: 0.88, blue: 0.82)
        }
    }

    /// Deep muted counterpart for dark mode bubbles and washes.
    public var pastelDark: Color {
        switch self {
        case .body:      Color(red: 0.10, green: 0.18, blue: 0.17)
        case .activity:  Color(red: 0.24, green: 0.18, blue: 0.09)
        case .recovery:  Color(red: 0.10, green: 0.15, blue: 0.26)
        case .nutrition: Color(red: 0.16, green: 0.13, blue: 0.27)
        case .money:     Color(red: 0.09, green: 0.18, blue: 0.12)
        case .habits:    Color(red: 0.26, green: 0.14, blue: 0.09)
        }
    }
```

And to `LifeOSTokens`:

```swift
    /// Soft companion to `accent`: the track behind a filled bar, the wash
    /// behind an accent icon.
    public static let accentSoft = AdaptiveColor(
        light: Color(red: 0.99, green: 0.88, blue: 0.82),
        dark: Color(red: 0.33, green: 0.16, blue: 0.10)
    )

    /// Anomaly banner surfaces. Red enough to interrupt, soft enough to live
    /// on the cream canvas.
    public static let alertBackground = AdaptiveColor(
        light: Color(red: 1.00, green: 0.92, blue: 0.92),
        dark: Color(red: 0.28, green: 0.09, blue: 0.09)
    )
    public static let alertText = AdaptiveColor(
        light: Color(red: 0.78, green: 0.16, blue: 0.16),
        dark: Color(red: 1.00, green: 0.58, blue: 0.55)
    )

    /// The one card shadow. Light mode only; dark mode separates surfaces by
    /// tone, and a black shadow on a black canvas is invisible cost.
    public static let cardShadow = Color.black.opacity(0.06)
```

- [ ] **Step 5: Run tests**: `swift test --filter TokensTests`. Expected: PASS (all, including pre-existing).

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/Tokens.swift LifeOSKit/Tests/DesignSystemTests/TokensTests.swift
git commit -m "feat(design): pastel hues, accentSoft and alert tokens for the light-card restyle"
```

---

### Task 2: AnomalyEvaluation (pure logic, TDD)

**Files:**
- Create: `LifeOSKit/Sources/Persistence/AnomalyEvaluation.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/AnomalyEvaluationTests.swift`

**Interfaces:**
- Produces (all `public`, consumed by Task 7):

```swift
struct AnomalyFinding: Equatable, Sendable, Identifiable {
    enum Direction: Sendable, Equatable { case above, below }
    let metric: String        // display name, e.g. "Resting HR"
    let todayValue: Double
    let baseline: Double
    let direction: Direction
    var id: String { metric }
    init(metric: String, todayValue: Double, baseline: Double, direction: Direction)
}
enum AnomalyThreshold: Sendable, Equatable {
    case relativeAbove(Double)  // flag when today >= baseline * (1 + fraction)
    case relativeBelow(Double)  // flag when today <= baseline * (1 - fraction)
    case absoluteAbove(Double)  // flag when today >= baseline + delta
    case absoluteBelow(Double)  // flag when today <= baseline - delta
}
enum AnomalyEvaluation {
    static let minimumBaselineDays = 7
    static func baseline(from history: [Double?]) -> Double?
    static func evaluate(metric: String, today: Double?, history: [Double?],
                         threshold: AnomalyThreshold) -> AnomalyFinding?
}
```

- [ ] **Step 1: Read one existing test file** (`LIfeOSKit/Tests/PersistenceTests/GoalEvaluationTests.swift`) to copy the test framework style and imports exactly.

- [ ] **Step 2: Write failing tests** in `LifeOSKit/Tests/PersistenceTests/AnomalyEvaluationTests.swift` (adapt syntax to the file read in Step 1; the cases below are required):

```swift
import Testing
@testable import Persistence

@Suite struct AnomalyEvaluationTests {
    // Baseline
    @Test func baselineIsMeanOfNonNilHistory() {
        let history: [Double?] = [50, nil, 60, 55, 45, 50, 60, 50]  // 7 readings
        #expect(AnomalyEvaluation.baseline(from: history) == 370.0 / 7.0)
    }
    @Test func baselineNeedsSevenReadings() {
        let sparse: [Double?] = [50, 51, 52, 53, 54, 55]  // 6 readings
        #expect(AnomalyEvaluation.baseline(from: sparse) == nil)
    }

    // No data → no verdict, never a finding
    @Test func nilTodayProducesNothing() {
        let history: [Double?] = Array(repeating: 50.0, count: 14)
        #expect(AnomalyEvaluation.evaluate(metric: "Resting HR", today: nil,
                history: history, threshold: .relativeAbove(0.10)) == nil)
    }
    @Test func insufficientBaselineProducesNothing() {
        #expect(AnomalyEvaluation.evaluate(metric: "Resting HR", today: 90,
                history: [50, 50], threshold: .relativeAbove(0.10)) == nil)
    }

    // relativeAbove: baseline 50, +10% → boundary at 55
    @Test func relativeAboveFlagsAtBoundary() {
        let history: [Double?] = Array(repeating: 50.0, count: 14)
        let finding = AnomalyEvaluation.evaluate(metric: "Resting HR", today: 55,
                history: history, threshold: .relativeAbove(0.10))
        #expect(finding == AnomalyFinding(metric: "Resting HR", todayValue: 55,
                                          baseline: 50, direction: .above))
    }
    @Test func relativeAboveStaysQuietBelowBoundary() {
        let history: [Double?] = Array(repeating: 50.0, count: 14)
        #expect(AnomalyEvaluation.evaluate(metric: "Resting HR", today: 54.9,
                history: history, threshold: .relativeAbove(0.10)) == nil)
    }

    // relativeBelow: baseline 60, −30% → boundary at 42
    @Test func relativeBelowFlagsDrop() {
        let history: [Double?] = Array(repeating: 60.0, count: 14)
        let finding = AnomalyEvaluation.evaluate(metric: "HRV", today: 40,
                history: history, threshold: .relativeBelow(0.30))
        #expect(finding?.direction == .below)
    }

    // absoluteAbove: baseline 33.0, +1.0°C → boundary at 34.0
    @Test func absoluteAboveFlagsSkinTemp() {
        let history: [Double?] = Array(repeating: 33.0, count: 14)
        let finding = AnomalyEvaluation.evaluate(metric: "Skin temp", today: 34.2,
                history: history, threshold: .absoluteAbove(1.0))
        #expect(finding?.direction == .above)
    }

    // absoluteBelow: baseline 97.0, −3 points → boundary at 94.0
    @Test func absoluteBelowFlagsSpo2() {
        let history: [Double?] = Array(repeating: 97.0, count: 14)
        let finding = AnomalyEvaluation.evaluate(metric: "Blood oxygen", today: 93.5,
                history: history, threshold: .absoluteBelow(3.0))
        #expect(finding?.direction == .below)
    }
    @Test func normalDayProducesNothing() {
        let history: [Double?] = Array(repeating: 97.0, count: 14)
        #expect(AnomalyEvaluation.evaluate(metric: "Blood oxygen", today: 96.8,
                history: history, threshold: .absoluteBelow(3.0)) == nil)
    }
}
```

- [ ] **Step 3: Run to verify failure**: `swift test --filter AnomalyEvaluationTests`. Expected: compile error, `AnomalyEvaluation` not found.

- [ ] **Step 4: Implement** `LifeOSKit/Sources/Persistence/AnomalyEvaluation.swift`:

```swift
import Foundation

/// One vital sitting outside its own recent range.
///
/// Wording rule for anything rendered from this: descriptive, never
/// diagnostic. "Well above your baseline" is a fact; "see a doctor" is a
/// claim this data cannot support.
public struct AnomalyFinding: Equatable, Sendable, Identifiable {
    public enum Direction: Sendable, Equatable { case above, below }

    public let metric: String
    public let todayValue: Double
    public let baseline: Double
    public let direction: Direction

    public var id: String { metric }

    public init(metric: String, todayValue: Double, baseline: Double, direction: Direction) {
        self.metric = metric
        self.todayValue = todayValue
        self.baseline = baseline
        self.direction = direction
    }
}

/// How far from baseline counts as abnormal, per metric. Percent for metrics
/// that scale with the person (heart rate), absolute for metrics with a
/// physiological unit (a degree of skin temperature means the same at any
/// baseline).
public enum AnomalyThreshold: Sendable, Equatable {
    case relativeAbove(Double)
    case relativeBelow(Double)
    case absoluteAbove(Double)
    case absoluteBelow(Double)
}

public enum AnomalyEvaluation {
    /// Below this many actual readings the baseline is noise, and a noisy
    /// baseline raises false alarms. No baseline → no verdict, same as the
    /// app-wide rule that absence of data is never a judgement.
    public static let minimumBaselineDays = 7

    public static func baseline(from history: [Double?]) -> Double? {
        let readings = history.compactMap { $0 }
        guard readings.count >= minimumBaselineDays else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    public static func evaluate(
        metric: String, today: Double?, history: [Double?],
        threshold: AnomalyThreshold
    ) -> AnomalyFinding? {
        guard let today, let baseline = baseline(from: history) else { return nil }

        let flagged: AnomalyFinding.Direction? = switch threshold {
        case .relativeAbove(let fraction):
            today >= baseline * (1 + fraction) ? .above : nil
        case .relativeBelow(let fraction):
            today <= baseline * (1 - fraction) ? .below : nil
        case .absoluteAbove(let delta):
            today >= baseline + delta ? .above : nil
        case .absoluteBelow(let delta):
            today <= baseline - delta ? .below : nil
        }

        guard let flagged else { return nil }
        return AnomalyFinding(metric: metric, todayValue: today,
                              baseline: baseline, direction: flagged)
    }
}
```

- [ ] **Step 5: Run tests**: `swift test --filter AnomalyEvaluationTests`. Expected: all PASS.

- [ ] **Step 6: Run the whole package**: `swift test`. Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Persistence/AnomalyEvaluation.swift LifeOSKit/Tests/PersistenceTests/AnomalyEvaluationTests.swift
git commit -m "feat(persistence): baseline anomaly evaluation for vitals"
```

---

### Task 3: New display components — AlertBanner, IconBubbleTile, RoundedBarChart

Pure additive SwiftUI in the package; verified by package build + previews.

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/AlertBanner.swift`
- Create: `LifeOSKit/Sources/DesignSystem/IconBubbleTile.swift`
- Create: `LifeOSKit/Sources/DesignSystem/RoundedBarChart.swift`

**Interfaces:**
- Consumes: Task 1 tokens (`alertBackground`, `alertText`, `accentSoft`, `cardShadow`, `ModuleHue.pastel/pastelDark`).
- Produces:
  - `AlertBanner(messages: [String])` — renders nothing when `messages` is empty.
  - `IconBubbleTile(icon: String, hue: ModuleHue, label: String, value: String?, unit: String? = nil)` — card-shaped stat with pastel icon bubble; nil value renders "—".
  - `RoundedBarChart.Bar(id: Date, label: String, value: Double?)` and `RoundedBarChart(bars: [Bar], unit: String)` — two-tone rounded bars, nil-valued days render a low stub in `dotMissed`.

- [ ] **Step 1: Write `AlertBanner.swift`**

```swift
import SwiftUI

/// The red interruption card: something in the data sits outside the reader's
/// own range. Facts only — the metric and the direction. Never advice.
public struct AlertBanner: View {
    private let messages: [String]
    @Environment(\.colorScheme) private var scheme

    public init(messages: [String]) {
        self.messages = messages
    }

    public var body: some View {
        // No anomalies is silence, not an empty red frame.
        if !messages.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(Circle().fill(LifeOSTokens.alertText.resolve(scheme).opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .font(.system(size: 14, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.alertBackground.resolve(scheme))
            )
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AlertBanner(messages: ["Resting HR is well above your 2-week baseline",
                               "Skin temp is well above your 2-week baseline"])
        AlertBanner(messages: [])
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
```

- [ ] **Step 2: Write `IconBubbleTile.swift`**

```swift
import SwiftUI

/// The reference design's stat card: an icon in a pastel bubble, a quiet
/// label, and a big dark number. Sits directly on the canvas as a card.
public struct IconBubbleTile: View {
    private let icon: String
    private let hue: ModuleHue
    private let label: String
    private let value: String?
    private let unit: String?
    @Environment(\.colorScheme) private var scheme

    /// `value == nil` renders an em dash, never a zero.
    public init(icon: String, hue: ModuleHue, label: String, value: String?, unit: String? = nil) {
        self.icon = icon
        self.hue = hue
        self.label = label
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    .lineLimit(2, reservesSpace: true)
                Spacer(minLength: 4)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(scheme == .dark ? hue.pastelDark : hue.pastel))
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .opacity(value == nil ? 0.4 : 1)
                if let unit, value != nil {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
                .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 12, y: 4)
        )
    }
}

#Preview {
    HStack(spacing: 12) {
        IconBubbleTile(icon: "flame.fill", hue: .activity, label: "Calories Today", value: "1,450", unit: "kcal")
        IconBubbleTile(icon: "drop.fill", hue: .recovery, label: "Drink Water", value: nil, unit: "ml")
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
```

- [ ] **Step 3: Write `RoundedBarChart.swift`**

```swift
import SwiftUI

/// The reference design's weekly chart: a full-height soft track per day with
/// a solid rounded bar inside it, scaled to the week's maximum.
public struct RoundedBarChart: View {
    public struct Bar: Identifiable, Equatable, Sendable {
        public let id: Date
        public let label: String
        public let value: Double?

        public init(id: Date, label: String, value: Double?) {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    private let bars: [Bar]
    @Environment(\.colorScheme) private var scheme

    public init(bars: [Bar]) {
        self.bars = bars
    }

    public var body: some View {
        let peak = max(bars.compactMap(\.value).max() ?? 1, 1)

        HStack(alignment: .bottom, spacing: 10) {
            ForEach(bars) { bar in
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            // The track: always full height, so a light week
                            // still reads as seven days, not four.
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LifeOSTokens.accentSoft.resolve(scheme))
                            if let value = bar.value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LifeOSTokens.accent)
                                    .frame(height: max(geo.size.height * value / peak, 10))
                            } else {
                                // A day with no reading is a gap, not a zero.
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(LifeOSTokens.dotMissed.resolve(scheme))
                                    .frame(height: 6)
                            }
                        }
                    }

                    Text(bar.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
        .frame(height: 150)
    }
}

#Preview {
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    RoundedBarChart(bars: days.enumerated().map { index, label in
        RoundedBarChart.Bar(id: Date().addingTimeInterval(Double(index) * 86_400),
                            label: label,
                            value: index == 4 ? nil : Double(200 + index * 130))
    })
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
```

- [ ] **Step 4: Build the package**: `cd /Users/shivvyas/LIfeOS/LifeOSKit && swift build`. Expected: succeeds.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/AlertBanner.swift LifeOSKit/Sources/DesignSystem/IconBubbleTile.swift LifeOSKit/Sources/DesignSystem/RoundedBarChart.swift
git commit -m "feat(design): alert banner, icon bubble tile and rounded bar chart"
```

---

### Task 4: PillNavBar

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/PillNavBar.swift`

**Interfaces:**
- Produces: `PillNavItem<Tab: Hashable>(value: Tab, systemImage: String, label: String)` and `PillNavBar<Tab: Hashable>(selection: Binding<Tab>, items: [PillNavItem<Tab>])`. Consumed by Task 9 (`RootView`).

- [ ] **Step 1: Write `PillNavBar.swift`**

```swift
import SwiftUI

/// One tab in the floating pill bar.
public struct PillNavItem<Tab: Hashable>: Identifiable {
    public let value: Tab
    public let systemImage: String
    public let label: String

    public var id: Tab { value }

    public init(value: Tab, systemImage: String, label: String) {
        self.value = value
        self.systemImage = systemImage
        self.label = label
    }
}

/// The app's navigation: a floating capsule of circular icon buttons, the
/// selected one a dark filled circle. Replaces the system tab bar, so it owns
/// what the system gave free: 44pt+ targets, labels, and selection traits.
public struct PillNavBar<Tab: Hashable>: View {
    @Binding private var selection: Tab
    private let items: [PillNavItem<Tab>]
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Tab>, items: [PillNavItem<Tab>]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected
                            ? LifeOSTokens.canvas.resolve(scheme)
                            : LifeOSTokens.secondaryText.resolve(scheme))
                        .frame(width: 52, height: 52)
                        .background {
                            if isSelected {
                                Circle().fill(LifeOSTokens.primaryText.resolve(scheme))
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background(
            Capsule().fill(LifeOSTokens.cardSurface.resolve(scheme))
                .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.12), radius: 16, y: 6)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}

#Preview {
    @Previewable @State var tab = 0
    ZStack(alignment: .bottom) {
        LifeOSTokens.canvas.resolve(.light)
        PillNavBar(selection: $tab, items: [
            PillNavItem(value: 0, systemImage: "circle.grid.3x3.fill", label: "Today"),
            PillNavItem(value: 1, systemImage: "heart.fill", label: "Health"),
            PillNavItem(value: 2, systemImage: "dollarsign", label: "Money"),
            PillNavItem(value: 3, systemImage: "checklist", label: "Plan"),
        ])
        .padding(.bottom, 20)
    }
}
```

- [ ] **Step 2: Build the package**: `swift build`. Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/PillNavBar.swift
git commit -m "feat(design): floating pill nav bar"
```

---

### Task 5: WeekStrip with ring-progress day cells

Signature stays source-compatible (new parameter has a default), so existing call sites keep compiling. The old `onGradient`-tinted look is replaced with adaptive token colors; it will look slightly off on the still-gradient Body canvas until Task 6 flips the canvas — acceptable mid-branch.

**Files:**
- Rewrite: `LifeOSKit/Sources/DesignSystem/WeekStrip.swift`

**Interfaces:**
- Produces: `WeekStrip(selection: Binding<Date>, progress: [Date: Double] = [:], calendar: Calendar = .current, today: Date = .now)` — `progress` keyed by `calendar.startOfDay`, values clamped 0…1, drawn as a ring around the day number. Consumed by Task 8/9.

- [ ] **Step 1: Rewrite `WeekStrip.swift`**

```swift
import SwiftUI

/// The day selector across the top of a domain screen: weekday above a
/// circled day number, with an optional per-day progress ring — the reference
/// design's calendar strip.
public struct WeekStrip: View {
    @Binding private var selection: Date
    private let progress: [Date: Double]
    private let calendar: Calendar
    private let today: Date
    @Environment(\.colorScheme) private var scheme

    /// `progress` is keyed by `calendar.startOfDay(for:)`. Days without an
    /// entry show a bare ring track — no data is a gap, not an empty score.
    public init(selection: Binding<Date>, progress: [Date: Double] = [:],
                calendar: Calendar = .current, today: Date = .now) {
        self._selection = selection
        self.progress = progress
        self.calendar = calendar
        self.today = today
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public var body: some View {
        let startOfToday = calendar.startOfDay(for: today)

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let dayStart = calendar.startOfDay(for: day)
                let isSelected = calendar.isDate(day, inSameDayAs: selection)
                let isFuture = dayStart > startOfToday
                let ring = progress[dayStart].map { min(max($0, 0), 1) }

                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

                    ZStack {
                        Circle()
                            .stroke(LifeOSTokens.dotMissed.resolve(scheme), lineWidth: 2.5)
                        if let ring, !isFuture {
                            Circle()
                                .trim(from: 0, to: ring)
                                .stroke(LifeOSTokens.accent,
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    }
                    .frame(width: 36, height: 36)
                    .background {
                        if isSelected {
                            Circle().fill(LifeOSTokens.accentSoft.resolve(scheme))
                        }
                    }
                }
                .opacity(isFuture ? 0.35 : 1)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { if !isFuture { selection = day } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

#Preview {
    @Previewable @State var selection = Date()
    let calendar = Calendar.current
    let week = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
    WeekStrip(
        selection: $selection,
        progress: [calendar.startOfDay(for: week): 0.8,
                   calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: week)!): 0.45]
    )
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
```

- [ ] **Step 2: Build the package**: `swift build`. Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/WeekStrip.swift
git commit -m "feat(design): ring-progress week strip"
```

---

### Task 6: The flip — flat canvas, SoftCard, and app-wide token migration

This task deletes `LifeOSTokens.onGradient`, flattens `GradientCanvas`, consolidates cards into `SoftCard`, and fixes every call site in one atomic commit so the build never lands broken. The compiler is the checklist: after the package change, every remaining use of `onGradient`, `GlassCard`, or `SolidCard` is a build error to fix.

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/Tokens.swift` (delete `onGradient`; revalue `tileSurface`)
- Modify: `LifeOSKit/Sources/DesignSystem/GradientCanvas.swift` (flat + wash)
- Rewrite: `LifeOSKit/Sources/DesignSystem/GlassCard.swift` → delete; Create: `LifeOSKit/Sources/DesignSystem/SoftCard.swift`
- Modify: `LifeOSKit/Sources/DesignSystem/MetricTile.swift` (MetricTile + SegmentedPill)
- Modify: `LifeOSKit/Sources/DesignSystem/DotBloom.swift`
- Modify (app target, compiler-driven): `LIfeOS/Features/Body/View/BodyHubScreen.swift`, `LIfeOS/Features/Body/View/BodyScreen.swift`, `LIfeOS/Features/Body/View/WellnessSection.swift`, `LIfeOS/Features/Activity/View/ActivityScreen.swift`, `LIfeOS/Features/Recovery/View/RecoveryScreen.swift`, `LIfeOS/Features/Recovery/View/WhoopDetailScreen.swift`, `LIfeOS/Features/Money/View/MoneyScreen.swift`, `LIfeOS/Features/Plan/View/PlanScreen.swift`, `LIfeOS/Features/Plan/View/ContentCalendar.swift`, `LIfeOS/Features/Today/View/TodayScreen.swift`, `LIfeOS/Features/Today/View/DayDetailSheet.swift`, `LIfeOS/Features/Onboarding/View/IntroScreen.swift`, plus any other file the compiler flags.

**Interfaces:**
- Produces: `SoftCard { }` (replaces both `GlassCard` and `SolidCard`); `GradientCanvas(hue:)` unchanged signature, new flat rendering. Consumed everywhere.
- Deletes: `LifeOSTokens.onGradient`, `GlassCard`, `SolidCard`.

**Substitution rules (apply mechanically at every compiler error):**

| Old | New |
|---|---|
| `LifeOSTokens.onGradient` as text/foreground | `LifeOSTokens.primaryText.resolve(scheme)` (add `@Environment(\.colorScheme) private var scheme` to the view if missing) |
| `LifeOSTokens.onGradient.opacity(x)` as text | `LifeOSTokens.secondaryText.resolve(scheme)` |
| `Capsule().fill(LifeOSTokens.onGradient.opacity(...))` (capsule/chip backgrounds) | `Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme))` |
| `GlassCard {` / `SolidCard {` | `SoftCard {` |
| `LifeOSTokens.primaryText.resolve(.light)` / `tileSurface.resolve(.light)` (hardcoded `.light` on gradient screens, e.g. `MoneyScreen.emptyState`, `PlanScreen` buttons) | resolve with the view's real `scheme` |

- [ ] **Step 1: Tokens.** In `Tokens.swift`: delete the `onGradient` declaration entirely. Revalue `tileSurface` so tiles read as solid cards on the light canvas:

```swift
    /// Surface for repeated tiles and rows. Since the canvas went light this
    /// is a solid card tone, not a translucency: translucent white over a
    /// near-white canvas is invisible.
    public static let tileSurface = AdaptiveColor(
        light: .white,
        dark: Color(white: 0.13)
    )
```

- [ ] **Step 2: GradientCanvas.** Replace the body's `LinearGradient` with a flat canvas plus a subtle pastel wash (keep the type name and init signature; update both previews to show light and dark):

```swift
    public var body: some View {
        ZStack(alignment: .top) {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()

            // A whisper of the module's identity at the top. The hue survives
            // the restyle as a tint, not a paint job.
            LinearGradient(
                colors: [(scheme == .dark ? hue.pastelDark : hue.pastel).opacity(scheme == .dark ? 0.7 : 0.55),
                         .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .ignoresSafeArea(edges: .top)

            content
        }
    }
```

Also update the doc comment: it is no longer "saturated at the top".

- [ ] **Step 3: SoftCard.** Delete `GlassCard.swift`; create `SoftCard.swift`:

```swift
import SwiftUI

/// The one card. White, rounded, soft-shadowed on the light canvas; a tonal
/// step up from the background in dark mode, where a shadow buys nothing.
///
/// The shadow is an offscreen pass, so this is screen furniture: never the
/// content of a long repeated list cell (use `tileSurface` rows for those).
public struct SoftCard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
                    .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow,
                            radius: 12, y: 4)
            )
    }
}
```

- [ ] **Step 4: SegmentedPill + MetricTile** (in `MetricTile.swift`). MetricTile: add a light-mode shadow to its background so tiles separate from the canvas:

```swift
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LifeOSTokens.tileSurface.resolve(scheme))
                .shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 8, y: 2)
        )
```

SegmentedPill: unselected text `LifeOSTokens.secondaryText.resolve(scheme)`; selected segment background `Capsule().fill(LifeOSTokens.cardSurface.resolve(scheme)).shadow(color: scheme == .dark ? .clear : LifeOSTokens.cardShadow, radius: 6, y: 2)`; container background `Capsule().fill(LifeOSTokens.primaryText.resolve(scheme).opacity(0.06))`.

- [ ] **Step 5: DotBloom** (`colour(at:isFilled:)`): unfilled → `LifeOSTokens.dotFuture.resolve(scheme)`, filled non-accent → `LifeOSTokens.primaryText.resolve(scheme)` (add the `@Environment(\.colorScheme)` property — it already has one). Fix its preview to use the flat canvas.

- [ ] **Step 6: Build the package**: `swift build`. Fix any straggler in package sources (previews included). Expected: succeeds.

- [ ] **Step 7: Build the app** and fix every compiler error using the substitution table:

```bash
cd /Users/shivvyas/LIfeOS && xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error|BUILD" | head -40
```

Iterate file by file until `** BUILD SUCCEEDED **`. Known call sites: `BodyHubScreen` (WeekStrip/hero tints), `ActivityScreen` (hero + "Workouts" header), `RecoveryScreen` (hero, band label stays `band.color`, trends capsule, sync line), `WellnessSection` (hero), `BodyScreen` (hero), `MoneyScreen` (hero, verdict chip, empty state — also fix its hardcoded `.resolve(.light)`), `PlanScreen` (empty state, add-button — fix `.resolve(.light)`), `ContentCalendar`, `TodayScreen` (SolidCard→SoftCard), `DayDetailSheet`, `IntroScreen`, `WhoopDetailScreen`.

- [ ] **Step 8: Run package tests**: `swift test`. Expected: PASS (TokensTests may need updating if any asserted `onGradient` — update the test, it tested a deleted token).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(design)!: flat light-card restyle — flatten canvas, SoftCard, retire onGradient"
```

---

### Task 7: Snapshot data — anomalies and weekly calories

**Files:**
- Modify: `LIfeOS/Features/Recovery/Model/RecoverySnapshot.swift`
- Modify: `LIfeOS/Features/Recovery/ViewModel/RecoveryViewModel.swift`
- Modify: `LIfeOS/Features/Activity/Model/ActivitySnapshot.swift`
- Modify: `LIfeOS/Features/Activity/ViewModel/ActivityViewModel.swift`

**Interfaces:**
- Consumes: `AnomalyEvaluation`, `AnomalyFinding`, `AnomalyThreshold` from Task 2 (`import Persistence` already present in the VM).
- Produces:
  - `RecoverySnapshot.anomalies: [AnomalyFinding]` (default `[]`)
  - `RecoverySnapshot.weekRecovery: [Date: Double]` (default `[:]`) — startOfDay → recovery fraction 0…1, for the week strip rings
  - `ActivitySnapshot.weekCalories: [DayValue]` where `struct DayValue: Equatable, Identifiable { let id: Date; let value: Double? }` — 7 entries, oldest first, ending on the selected day

- [ ] **Step 1: RecoverySnapshot.** Add fields (after `nights`):

```swift
    /// Vitals sitting outside the reader's own trailing baseline. Empty means
    /// quiet — either genuinely normal or not enough data to judge.
    var anomalies: [AnomalyFinding] = []

    /// startOfDay → recovery fraction (0…1) for the strip's rings.
    var weekRecovery: [Date: Double] = [:]
```

Add `import Persistence` to the snapshot file (it currently imports `Foundation` and `DesignSystem`). `AnomalyFinding` is `Equatable`, so the snapshot stays `Equatable`.

- [ ] **Step 2: RecoveryViewModel.** In `load()`, after `nights` is computed, build both fields and pass them into the snapshot initializer:

```swift
            // History excludes the selected day: a spike must not drag the
            // baseline toward itself on the very day it is being judged.
            func history(_ series: TrendSeries) -> [Double?] {
                series.points.dropLast().map(\.value)
            }

            let restingTrend = trend(rows, from: start, to: end) { $0.restingHR }
            let respTrend = trend(rows, from: start, to: end) { $0.respiratoryRate }
            let skinTrend = trend(rows, from: start, to: end) { $0.skinTempCelsius }
            let spo2TrendSeries = trend(rows, from: start, to: end) { $0.spo2Percentage }
            let hrvTrendSeries = trend(rows, from: start, to: end) { $0.hrvMs }

            let anomalies = [
                AnomalyEvaluation.evaluate(metric: "Resting HR", today: day?.restingHR,
                    history: history(restingTrend), threshold: .relativeAbove(0.10)),
                AnomalyEvaluation.evaluate(metric: "Respiratory rate", today: day?.respiratoryRate,
                    history: history(respTrend), threshold: .relativeAbove(0.08)),
                AnomalyEvaluation.evaluate(metric: "Skin temp", today: day?.skinTempCelsius,
                    history: history(skinTrend), threshold: .absoluteAbove(1.0)),
                AnomalyEvaluation.evaluate(metric: "Blood oxygen", today: day?.spo2Percentage,
                    history: history(spo2TrendSeries), threshold: .absoluteBelow(3.0)),
                AnomalyEvaluation.evaluate(metric: "HRV", today: day?.hrvMs,
                    history: history(hrvTrendSeries), threshold: .relativeBelow(0.30)),
            ].compactMap { $0 }

            var weekRecovery: [Date: Double] = [:]
            for row in rows {
                if let pct = row.whoopRecoveryPct {
                    weekRecovery[calendar.startOfDay(for: row.date)] = pct / 100
                }
            }
```

Reuse these local trends for the snapshot's existing `restingHRTrend`, `respiratoryRateTrend`, `skinTempTrend`, `spo2Trend`, `hrvTrend` fields instead of computing them twice. Pass `anomalies: anomalies, weekRecovery: weekRecovery` in the `RecoverySnapshot(...)` init.

- [ ] **Step 3: ActivitySnapshot.** Add:

```swift
/// One day's value in a small weekly series; nil is a gap, never zero.
struct DayValue: Equatable, Identifiable {
    let id: Date
    let value: Double?
}
```

and to `ActivitySnapshot`: `var weekCalories: [DayValue] = []`.

- [ ] **Step 4: ActivityViewModel.** In `load()`, replace the single-day fetch with a 7-day window ending on the selected day, keeping the selected-day extraction:

```swift
            let end = selectedDate
            let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            let rows = try store.metrics(from: start, to: end)
            let today = rows.first { calendar.isDate($0.date, inSameDayAs: end) }

            var byDay: [Date: Double] = [:]
            for row in rows {
                if let kcal = row.whoopCalories ?? row.activeEnergyKcal {
                    byDay[calendar.startOfDay(for: row.date)] = kcal
                }
            }
            var weekCalories: [DayValue] = []
            var cursor = calendar.startOfDay(for: start)
            let last = calendar.startOfDay(for: end)
            while cursor <= last {
                weekCalories.append(DayValue(id: cursor, value: byDay[cursor]))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
```

Pass `weekCalories: weekCalories` into the `ActivitySnapshot(...)` init. (Note `row.whoopCalories ?? row.activeEnergyKcal` — Whoop's day-cycle calories are the primary source; `activeEnergyKcal` is the fallback for seed data.)

- [ ] **Step 5: Build the app** (same `xcodebuild` command). Expected: `** BUILD SUCCEEDED **` — nothing consumes the new fields yet, but inits and imports must line up.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Recovery LIfeOS/Features/Activity
git commit -m "feat(health): anomaly findings and weekly calories in snapshots"
```

---

### Task 8: Health and Fitness segment views

**Files:**
- Create: `LIfeOS/Features/Health/Model/HealthSection.swift`
- Create: `LIfeOS/Features/Health/View/StatGroup.swift` (move `StatGroup` verbatim from `RecoveryScreen.swift`)
- Create: `LIfeOS/Features/Health/View/HealthSegmentView.swift`
- Create: `LIfeOS/Features/Health/View/FitnessSegmentView.swift`
- Modify: `LIfeOS/Features/Recovery/View/RecoveryScreen.swift` (delete `RecoverySection` + `StatGroup`; the file's remaining content moves out — delete the file if empty)
- Modify: `LIfeOS/Features/Activity/View/ActivityScreen.swift` (delete `ActivitySection`; move `WorkoutRow` into `FitnessSegmentView.swift`; delete the file)
- Delete: `LIfeOS/Features/Body/View/WellnessSection.swift` (journal card moves into `HealthSegmentView`)

New files must be added to the Xcode project. Check `LIfeOS.xcodeproj/project.pbxproj` first: if the project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+ folder references), files on disk are picked up automatically; otherwise edit `project.pbxproj` to register each new file (follow the pattern of an existing Features file).

**Interfaces:**
- Consumes: `AlertBanner`, `IconBubbleTile`, `RoundedBarChart`, `SoftCard`, `StatGroup`, `WeightSection`, `RecoveryBand`, `HeroNumeral`/`HeroEmptyState`, snapshots incl. Task 7 fields.
- Produces:
  - `enum HealthSection: String, CaseIterable, Identifiable { case health, fitness }` with `title: String` and `hue: ModuleHue` (`.health` → `.body`, `.fitness` → `.activity`)
  - `HealthSegmentView(recovery: RecoverySnapshot, weight: BodySnapshot, wellness: WellnessSnapshot, onAddJournal: @escaping () -> Void)`
  - `FitnessSegmentView(activity: ActivitySnapshot, recovery: RecoverySnapshot, wellness: WellnessSnapshot)`

- [ ] **Step 1: `HealthSection.swift`**

```swift
import Foundation
import DesignSystem

/// The Health tab's two halves: how the body is doing, and what it did.
enum HealthSection: String, CaseIterable, Identifiable {
    case health, fitness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health:  "Health"
        case .fitness: "Fitness"
        }
    }

    var hue: ModuleHue {
        switch self {
        case .health:  .body
        case .fitness: .activity
        }
    }
}
```

- [ ] **Step 2: `StatGroup.swift`** — move the `StatGroup` struct (with its `Row`) out of `RecoveryScreen.swift` verbatim into `LIfeOS/Features/Health/View/StatGroup.swift` (imports: `SwiftUI`, `DesignSystem`).

- [ ] **Step 3: `HealthSegmentView.swift`** — how the body is doing. Order: banner, recovery, sleep, vitals, weight, journal. The row builders (`sleepRows`, `vitalRows`, `dayRows` → vitals only here) and the `duration` helper move from the old `RecoverySection`; the journal card moves from `WellnessSection`; the trends link and sync line survive:

```swift
import SwiftUI
import DesignSystem
import Persistence

/// The Health half: is anything off, then how the body is doing — recovery,
/// sleep, vitals against their own baselines, weight, and the journal.
struct HealthSegmentView: View {
    let recovery: RecoverySnapshot
    let weight: BodySnapshot
    let wellness: WellnessSnapshot
    var onAddJournal: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            AlertBanner(messages: recovery.anomalies.map(Self.message))

            recoveryCard
            StatGroup(title: "Sleep", rows: sleepRows)
            StatGroup(title: "Vitals", rows: vitalRows)
            WeightSection(snapshot: weight)
            journalCard

            if recovery.hasAnyReading {
                NavigationLink {
                    WhoopDetailScreen(snapshot: recovery)
                } label: {
                    HStack(spacing: 6) {
                        Text("14-day trends").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(LifeOSTokens.accentSoft.resolve(scheme)))
                }
            }

            if let synced = recovery.syncedAt {
                Text("Synced \(Self.relative.localizedString(for: synced, relativeTo: .now))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
    }

    /// Descriptive, never diagnostic. The banner states the fact and stops.
    static func message(_ finding: AnomalyFinding) -> String {
        let direction = finding.direction == .above ? "well above" : "well below"
        return "\(finding.metric) is \(direction) your 2-week baseline"
    }

    @ViewBuilder
    private var recoveryCard: some View {
        if let pct = recovery.recoveryPct {
            let band = RecoveryBand.band(for: pct)
            SoftCard {
                VStack(spacing: 6) {
                    HeroNumeral(value: "\(Int(pct))", unit: "%", label: "Recovery")
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Text(band.label.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(band.color)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            HeroEmptyState(label: "Recovery", reason: "Connect Whoop in Settings")
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .padding(.top, 18)
        }
    }

    private var journalCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("JOURNAL")
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                    Spacer()
                    Button(wellness.hasEntryToday ? "Add another" : "Write today") { onAddJournal() }
                        .font(.system(size: 13, weight: .semibold))
                        .tint(LifeOSTokens.accent)
                }
                if wellness.journal.isEmpty {
                    Text("Nothing written yet. How did today feel?")
                        .font(.system(size: 14)).opacity(0.5)
                } else {
                    ForEach(wellness.journal.prefix(4)) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text).font(.system(size: 15)).lineLimit(3)
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.system(size: 12)).opacity(0.45)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var sleepRows: [StatGroup.Row] {
        [
            .init(label: "Duration", value: recovery.sleepMinutes.map(Self.duration)),
            .init(label: "Performance", value: recovery.sleepPerformancePct.map { "\(Int($0))%" }),
            .init(label: "Efficiency", value: recovery.sleepEfficiencyPct.map { "\(Int($0))%" }),
            .init(label: "Consistency", value: recovery.sleepConsistencyPct.map { "\(Int($0))%" }),
            .init(label: "Sleep debt", value: recovery.sleepDebtMinutes.map(Self.duration)),
        ]
    }

    private var vitalRows: [StatGroup.Row] {
        [
            .init(label: "Blood oxygen",
                  value: recovery.spo2Percentage.map { String(format: "%.1f%%", $0) },
                  delta: recovery.spo2Trend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "Skin temp",
                  value: recovery.skinTempCelsius.map { String(format: "%.1f°C", $0) },
                  delta: recovery.skinTempTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "Respiratory rate",
                  value: recovery.respiratoryRate.map { String(format: "%.1f", $0) },
                  delta: recovery.respiratoryRateTrend.deltaFromAverage.map { String(format: "%+.1f", $0) }),
            .init(label: "HRV", value: recovery.hrvMs.map { "\(Int($0)) ms" }),
            .init(label: "Resting HR", value: recovery.restingHR.map { "\(Int($0)) bpm" }),
        ]
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
```

- [ ] **Step 4: `FitnessSegmentView.swift`** — what the body did. Calories chart, tiles, strain, workouts, weekly rollup. `WorkoutRow` moves here verbatim from `ActivityScreen.swift`:

```swift
import SwiftUI
import DesignSystem

/// The Fitness half: output. The weekly burn, today's movement, strain, the
/// sessions themselves, and how the training week is adding up.
struct FitnessSegmentView: View {
    let activity: ActivitySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            caloriesCard

            HStack(spacing: 12) {
                IconBubbleTile(icon: "figure.walk", hue: .body, label: "Steps",
                               value: activity.steps.map { $0.formatted() })
                IconBubbleTile(icon: "bolt.fill", hue: .activity, label: "Active Time",
                               value: activity.exerciseMinutes.map { "\($0)" }, unit: "min")
            }

            HStack(spacing: 12) {
                IconBubbleTile(icon: "gauge.with.needle", hue: .habits, label: "Strain",
                               value: recovery.dayStrain.map { String(format: "%.1f", $0) })
                IconBubbleTile(icon: "heart.fill", hue: .recovery, label: "Avg HR",
                               value: recovery.averageHR.map { "\(Int($0))" }, unit: "bpm")
            }

            if !activity.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WORKOUTS")
                        .font(.system(size: 11, weight: .bold)).tracking(1)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    ForEach(activity.workouts) { WorkoutRow(workout: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            trainingCard
        }
    }

    private var caloriesCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calories Burnt").font(.system(size: 16, weight: .semibold))
                        Text("This week").font(.system(size: 12))
                            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    }
                    Spacer()
                    let total = activity.weekCalories.compactMap(\.value).reduce(0, +)
                    Text(total > 0 ? "\(Int(total).formatted()) kcal" : "—")
                        .font(.system(size: 15, weight: .semibold))
                }
                RoundedBarChart(bars: activity.weekCalories.map {
                    RoundedBarChart.Bar(
                        id: $0.id,
                        label: $0.id.formatted(.dateTime.weekday(.abbreviated)),
                        value: $0.value
                    )
                })
            }
        }
    }

    private var trainingCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("TRAINING")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.55)
                HStack {
                    Text(wellness.trainingVerdict ?? "—").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text("\(wellness.workoutDays)/\(wellness.workoutTarget) days")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LifeOSTokens.accent)
                }
                if let avg = wellness.averageExerciseMinutes {
                    Text("Avg session \(avg) min").font(.system(size: 13))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                }
            }
        }
    }
}

// WorkoutRow moves here VERBATIM from ActivityScreen.swift (struct WorkoutRow,
// including its detailLine helper). Do not restyle beyond what Task 6 already
// did to tileSurface.
```

- [ ] **Step 5: Deletions.** Remove `RecoverySection` from `RecoveryScreen.swift` (delete the file once only `RecoverySection` remained — `WhoopDetailScreen.swift` is a separate file and stays). Delete `ActivityScreen.swift` (after moving `WorkoutRow`). Delete `WellnessSection.swift`. `BodyHubScreen` still references deleted views — fix in the next step by updating it minimally OR proceed straight to Task 9 in the same working tree if executing inline. If this task must land green on its own: point `BodyHubScreen`'s `switch section` cases at the two new segment views temporarily:

```swift
                    switch section {
                    case .activity, .recovery:
                        FitnessSegmentView(activity: activity, recovery: recovery, wellness: wellness)
                    case .weight, .wellness:
                        HealthSegmentView(recovery: recovery, weight: weight,
                                          wellness: wellness, onAddJournal: onAddJournal)
                    }
```

(`BodyHubScreen` and `BodySection` are deleted for real in Task 9.)

- [ ] **Step 6: Build the app**. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(health): health and fitness segment views"
```

---

### Task 9: HealthHubScreen + RootView with PillNavBar

**Files:**
- Create: `LIfeOS/Features/Health/View/HealthHubScreen.swift`
- Delete: `LIfeOS/Features/Body/View/BodyHubScreen.swift`, `LIfeOS/Features/Body/Model/BodySection.swift`
- Modify: `LIfeOS/App/RootView.swift`

**Interfaces:**
- Consumes: `HealthSection`, `HealthSegmentView`, `FitnessSegmentView` (Task 8), `PillNavBar`/`PillNavItem` (Task 4), `WeekStrip(selection:progress:)` (Task 5), `RecoverySnapshot.weekRecovery` (Task 7).
- Produces: `HealthHubScreen(activity:weight:recovery:wellness:onAddJournal:section:selectedDate:)` with `section: Binding<HealthSection>`.

- [ ] **Step 1: `HealthHubScreen.swift`**

```swift
import SwiftUI
import DesignSystem

/// The Health tab: one week strip, two halves. Health is how the body is
/// doing; Fitness is what it did. Life OS is still not a fitness app.
struct HealthHubScreen: View {
    let activity: ActivitySnapshot
    let weight: BodySnapshot
    let recovery: RecoverySnapshot
    let wellness: WellnessSnapshot
    var onAddJournal: () -> Void = {}

    @Binding var section: HealthSection
    @Binding var selectedDate: Date

    var body: some View {
        GradientCanvas(hue: section.hue) {
            ScrollView {
                VStack(spacing: 22) {
                    WeekStrip(selection: $selectedDate, progress: recovery.weekRecovery)
                        .padding(.top, 4)

                    SegmentedPill(
                        selection: $section,
                        options: HealthSection.allCases.map { ($0, $0.title) }
                    )

                    switch section {
                    case .health:
                        HealthSegmentView(recovery: recovery, weight: weight,
                                          wellness: wellness, onAddJournal: onAddJournal)
                    case .fitness:
                        FitnessSegmentView(activity: activity, recovery: recovery,
                                           wellness: wellness)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: section)
    }
}
```

- [ ] **Step 2: RootView.** Changes, keeping everything else (sheets, `.task` blocks, `selectBodyDate`→rename `selectHealthDate`, `attachAll`, `reloadAll`) intact:
  - `@State private var bodySection = BodySection.activity` → `@State private var healthSection = HealthSection.health`; `bodyDate` → `healthDate`.
  - `enum AppTab { case today, body, money, plan }` → `case today, health, money, plan`.
  - Replace the whole `TabView { ... }.tabViewStyle(.sidebarAdaptable)` block with a switch plus overlays (the ZStack alignment stays `.bottomTrailing` for the FAB):

```swift
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch tab {
                case .today:
                    NavigationStack {
                        TodayScreen(snapshot: today.snapshot, onSelectDay: { today.select($0) })
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button { showSettings = true } label: {
                                        Image(systemName: "gearshape.fill")
                                    }
                                    .tint(LifeOSTokens.primaryText.resolve(scheme))
                                    .accessibilityLabel("Settings")
                                }
                            }
                    }
                case .health:
                    NavigationStack {
                        HealthHubScreen(
                            activity: activity.snapshot,
                            weight: weight.snapshot,
                            recovery: recovery.snapshot,
                            wellness: wellness.snapshot,
                            onAddJournal: { showJournal = true },
                            section: $healthSection,
                            selectedDate: Binding(
                                get: { healthDate },
                                set: { healthDate = $0; selectHealthDate($0) }
                            )
                        )
                    }
                case .money:
                    MoneyScreen(snapshot: money.snapshot) { showAddMoney = true }
                case .plan:
                    PlanScreen(
                        snapshot: plan.snapshot,
                        section: Binding(get: { plan.section }, set: { plan.section = $0 }),
                        onAdd: { showAddPlan = true },
                        onAdvance: { plan.advance(id: $0) },
                        onToggleHabit: { plan.toggleHabit(id: $0) },
                        onDelete: { plan.delete(id: $0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The pill owns the bottom center; the FAB keeps the corner.
            PillNavBar(selection: $tab, items: [
                PillNavItem(value: AppTab.today, systemImage: "circle.grid.3x3.fill", label: "Today"),
                PillNavItem(value: AppTab.health, systemImage: "heart.fill", label: "Health"),
                PillNavItem(value: AppTab.money, systemImage: "dollarsign", label: "Money"),
                PillNavItem(value: AppTab.plan, systemImage: "checklist", label: "Plan"),
            ])
            .frame(maxWidth: .infinity)          // centers the pill
            .padding(.bottom, 12)

            Button {
                showQuickLog = true
            } label: { /* unchanged FAB label */ }
            .padding(.trailing, metrics.gutter)
            .padding(.bottom, metrics.fabBottomInset)
            .accessibilityLabel("Quick log")
        }
```

  Note: the sidebar comment block above the old `.tabViewStyle` line goes away with it. iPad now uses the same centered pill (spec §3.1).

- [ ] **Step 3: Delete** `BodyHubScreen.swift` and `BodySection.swift`. Search the target for remaining references: `grep -rn "BodySection\|BodyHubScreen" LIfeOS/` → must return nothing.

- [ ] **Step 4: Build the app**. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Launch in the simulator and screenshot** (memory note: drive the simulator via AppleScript, no idb):

```bash
xcrun simctl boot "iPhone 16" 2>/dev/null; open -a Simulator
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/lifeos-dd build 2>&1 | tail -3
xcrun simctl install booted /tmp/lifeos-dd/Build/Products/Debug-iphonesimulator/LIfeOS.app
xcrun simctl launch booted shivvyas.LIfeOS
sleep 3 && xcrun simctl io booted screenshot /tmp/lifeos-today.png
```

Read the screenshot: pill nav visible at bottom center, FAB clear of it, light cream canvas. Then tap through to the Health tab (AppleScript per the memory file `driving-lifeos-ios-simulator.md`) and screenshot both segments.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(health)!: Health tab with Health/Fitness segments and floating pill nav"
```

---

### Task 10: Full verification pass

**Files:** none new — fixes only, wherever the pass finds problems.

- [ ] **Step 1: Package tests**: `cd /Users/shivvyas/LIfeOS/LifeOSKit && swift test`. Expected: all PASS.

- [ ] **Step 2: App build**: the standard `xcodebuild` command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Light-mode walk.** In the simulator, screenshot each tab (Today, Health-health, Health-fitness, Money, Plan) and the Day-detail + QuickLog sheets. Check: no white-on-white text, cards separate from canvas, week-strip rings render, banner absent when no anomalies, "—" (never 0) for missing data, pill nav hit targets work, FAB does not overlap the pill.

- [ ] **Step 4: Dark-mode walk**: `xcrun simctl ui booted appearance dark`, repeat the five screenshots. Check: canvas near-black, cards tonal (no invisible shadows), alert/pastel colors legible.
  Then restore: `xcrun simctl ui booted appearance light`.

- [ ] **Step 5: iPad spot check**: build & run on an available iPad simulator (`xcrun simctl list devices available | grep iPad`); screenshot Today and Health. Check: pill centered, content capped at `maxContentWidth`, no sidebar remnants.

- [ ] **Step 6: Empty-state check.** If Whoop is connected in the simulator's app state, this is covered by preview review instead: `HealthSegmentView` with default `RecoverySnapshot()` must show "Connect Whoop in Settings" and no banner.

- [ ] **Step 7: Fix anything found**, re-run Steps 1–2, then commit:

```bash
git add -A
git commit -m "fix(design): verification-pass fixes for the light-card restyle"
```

---

## Self-Review (completed)

- **Spec coverage:** §3.1 nav/tabs → Tasks 4, 9. §3.2 hub layout → Task 9. §3.3 Health segment (order incl. banner-first) → Task 8. §3.4 Fitness segment → Task 8. §3.5 detail nav → Tasks 8 (trends link) + 9. §4.1 tokens → Tasks 1, 6. §4.2 components → Tasks 3–6. §4.3 dark mode → every component + Task 10. §5 anomalies → Tasks 2, 7, 8 (wording rule in Global Constraints). §6 data flow → Tasks 7–9 (no schema change; VMs kept per the spec's "whichever keeps files small"). §7 empty states → preserved verbatim in moved code + Task 10 Step 6. §8 testing → Tasks 1, 2, 10. §9 out of scope → nothing here touches it.
- **Placeholder scan:** the two "verbatim move" instructions (`StatGroup`, `WorkoutRow`) reference exact existing code by name and location, not unwritten code. No TBDs.
- **Type consistency:** `AnomalyFinding`/`AnomalyThreshold`/`AnomalyEvaluation` signatures match between Tasks 2, 7, 8. `DayValue` defined Task 7, consumed Task 8. `PillNavItem`/`PillNavBar` match Tasks 4/9. `WeekStrip(selection:progress:)` matches Tasks 5/9. `HealthSection` matches Tasks 8/9. `SoftCard` introduced Task 6, consumed Tasks 8+.
