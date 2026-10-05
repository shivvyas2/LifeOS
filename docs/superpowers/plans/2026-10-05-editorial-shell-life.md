# Editorial shell header and Life tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put one shell header (assistant, LIFO, Start, avatar) on all five tabs and move the Life tab onto the editorial mono theme, with teaching empty states and design-preview pages to prove it.

**Architecture:** The header is a `ShellToolbar` view modifier in `DesignSystem` that reads two environment values `RootView` injects once (`quickActions`, new `shellProfile`), so Notes and Life, which own their own navigation stacks, draw the same bar. Life screens are pure functions of their view models; the masthead text is a pure `BoardHeadline` value in the `Sectors` package so it is unit tested, and every screen is composed from the existing `Editorial.swift` pieces plus a new `ink` chart style and a new `EditorialEmptyState`. Fixture-fed DEBUG preview pages render each screen without sign-in for screenshot review.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`@Suite`/`@Test`/`#expect`) in the `LifeOSKit` Swift package, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-05-editorial-shell-life-today-notes-coach-guide-design.md`, sections 1, 2, 6 (the `EditorialEmptyState` component only), 7 and 8 (PR 1).

## Global Constraints

- Paper is `LifeOSTokens.canvas`, ink is `LifeOSTokens.primaryText`, hairlines are `Editorial.rule(scheme)`, quiet text is `Editorial.quietInk(scheme)`. No new colours anywhere.
- One gradient field per screen at most (`EditorialField(.dusk)`); the accent (`LifeOSTokens.accent`) only for what is live or urgent.
- Every button uses `.buttonStyle(.editorial(role))`. No bare `Capsule().fill(LifeOSTokens.accent)` buttons.
- No per-module palette: `SectorPalette.tone`, `SectorPalette.hue` and `SectorPalette.cardInk` are deleted by the end of this plan. `SectorPalette.icon` stays.
- Fonts come only from `LifeOSType` or `Editorial.figure(_:)` / `Editorial.headline(_:)`. `scripts/check-typography.sh` must pass; it rejects any `.system(size: <number>` outside `Typography.swift`, and `Editorial.swift` already holds the two allowed computed sizes.
- The `LifeOSKit` package also builds for macOS (`swift test` runs there), so anything iOS-only inside `DesignSystem` goes under `#if os(iOS)` or `#if canImport(UIKit)`.
- `LIfeOS/` is a synchronized folder in the Xcode project: new files under it are picked up automatically; nothing is added to `project.pbxproj`.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution of any kind.
- Work happens in the worktree `.claude/worktrees/editorial-shell` on branch `feat/editorial-shell-life`, which already carries the spec commit.

## Review Focus

1. A sector with no closed month and no in-flight reading must show the teaching empty state, not an all-dashes deck: pinned by `LifeBoardViewModel` `isBlank` behaviour in Task 5's preview page `life-empty` and by `BoardHeadlineTests.closedWithNothingSaysSo` in Task 1.
2. `remainingDays == 1` must read "1 day left", never "1 days left": `BoardHeadlineTests.oneDayLeftIsSingular` in Task 1.
3. A deck band with no value draws its placeholder in quiet ink and VoiceOver still reads "not scored yet": kept from the existing `accessibilityText` in Task 6, checked on the `life` preview with the Accessibility Inspector label dump in Task 10.
4. Calling `RoundedBarChart(bars:)` with no style or hue must still compile and keep the accent look: `RoundedBarChartTests.accentIsTheDefault` in Task 2.
5. The avatar must appear on all five tabs and exactly once on Today (which used to add its own): checked visually on `shell` and each tab in Task 10, and by grep that `ProfileAvatar(` appears in `RootView.swift` zero times after Task 3.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/Sectors/BoardHeadline.swift` (new) | Pure masthead text for the Life board |
| `LifeOSKit/Tests/SectorsTests/BoardHeadlineTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/DesignSystem/RoundedBarChart.swift` | Gains `Style` with `.ink` |
| `LifeOSKit/Tests/DesignSystemTests/RoundedBarChartTests.swift` | Style tests |
| `LifeOSKit/Sources/DesignSystem/ProfileAvatar.swift` (new, moved) | The avatar, now shared |
| `LIfeOS/Components/View/ProfileAvatar.swift` (deleted) | |
| `LifeOSKit/Sources/DesignSystem/QuickActionsToolbar.swift` | `ShellProfile`, `ShellToolbar`, `shellToolbar()` |
| `LifeOSKit/Sources/DesignSystem/ActionFan.swift` | Word pill for a non-prominent action with a `shortLabel` |
| `LifeOSKit/Sources/DesignSystem/EditorialEmptyState.swift` (new) | Teaching empty state |
| `LIfeOS/App/RootView.swift` | Injects `shellProfile`, uses `shellToolbar()` on every tab, LIFO `shortLabel` |
| `LIfeOS/Features/Notes/View/NotesHubScreen.swift` | Drops the system title, adds the shell bar |
| `LIfeOS/Features/Life/ViewModel/LifeBoardViewModel.swift` | `month`, `lastClosedMonth`, `headline`, `isBlank`, default mode |
| `LIfeOS/Features/Life/View/LifeBoardScreen.swift` | Masthead, underline picker, empty state |
| `LIfeOS/Features/Life/View/CloseBanner.swift` | Editorial card |
| `LIfeOS/Features/Life/View/SectorStack.swift` | Paper deck, `SectorBandRow` |
| `LIfeOS/Features/Life/View/SectorDetailScreen.swift` | Field header, numbered sections |
| `LIfeOS/Features/Life/View/InFlightSectorScreen.swift` | Masthead, numbered sections |
| `LIfeOS/Features/Life/View/MonthlyCloseScreen.swift` | Masthead, figure card, done view |
| `LIfeOS/Features/Life/View/SectorPalette.swift` | Only `icon` remains |
| `LIfeOS/Features/Life/View/LifeDesignPreview.swift` (new, DEBUG) | Fixture pages `life`, `life-empty`, `life-detail`, `life-inflight`, `life-close`, `shell` |
| `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Routes those pages |

---

### Task 1: `BoardHeadline` in the Sectors package

**Files:**
- Create: `LifeOSKit/Sources/Sectors/BoardHeadline.swift`
- Test: `LifeOSKit/Tests/SectorsTests/BoardHeadlineTests.swift`

**Interfaces:**
- Consumes: `BoardSummary.lowest: LifeSector?`, `BoardSummary.biggestMover: (sector: LifeSector, delta: Int)?`, `LifeSector.title`.
- Produces: `public struct BoardHeadline { eyebrow, title, detail }` with `static func closed(month:lastClosed:summary:locale:)` and `static func inFlight(month:remainingDays:meanDecided:locale:)`. Task 5 renders it.

- [ ] **Step 1: Write the failing tests**

```swift
// LifeOSKit/Tests/SectorsTests/BoardHeadlineTests.swift
import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BoardHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var october: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 1))!
    }
    private var september: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    @Test func closedNamesTheMonthAndBothBoardFacts() {
        let summary = BoardSummary(scores: [.body: 8, .friends: 3], previous: [.body: 6, .friends: 3])
        let headline = BoardHeadline.closed(month: october, lastClosed: september, summary: summary, locale: en)
        #expect(headline.eyebrow == "Life · October")
        #expect(headline.title == "September closed")
        #expect(headline.detail == "Lowest: Friends · Biggest move: Body +2")
    }

    @Test func closedWithNothingSaysSo() {
        let headline = BoardHeadline.closed(month: october, lastClosed: nil,
                                            summary: BoardSummary(scores: [:], previous: [:]), locale: en)
        #expect(headline.title == "Nothing closed yet")
        #expect(headline.detail == nil)
    }

    @Test func closedOmitsAFactThatHasNoValue() {
        let summary = BoardSummary(scores: [.body: 8], previous: [:])
        let headline = BoardHeadline.closed(month: october, lastClosed: september, summary: summary, locale: en)
        #expect(headline.detail == "Lowest: Body")
    }

    @Test func inFlightCountsDownAndReportsDecided() {
        let headline = BoardHeadline.inFlight(month: october, remainingDays: 18, meanDecided: 0.624, locale: en)
        #expect(headline.eyebrow == "Life · October")
        #expect(headline.title == "18 days left")
        #expect(headline.detail == "62% of this month is decided")
    }

    @Test func oneDayLeftIsSingular() {
        let headline = BoardHeadline.inFlight(month: october, remainingDays: 1, meanDecided: nil, locale: en)
        #expect(headline.title == "1 day left")
        #expect(headline.detail == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter BoardHeadlineTests`
Expected: compile error, `cannot find 'BoardHeadline' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// LifeOSKit/Sources/Sectors/BoardHeadline.swift
import Foundation
import Persistence

/// The Life board's masthead, worked out once from what the board knows.
///
/// A value rather than view code so the wording is tested: the singular
/// "1 day left", the missing fact that is left out rather than rendered as
/// "Lowest: " with nothing after it.
public struct BoardHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String?

    public init(eyebrow: String, title: String, detail: String?) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    /// Closed mode: which month was closed last, and the two board facts.
    public static func closed(
        month: Date, lastClosed: Date?, summary: BoardSummary, locale: Locale = .current
    ) -> BoardHeadline {
        let title = lastClosed.map { "\(monthName($0, locale: locale)) closed" } ?? "Nothing closed yet"
        var facts: [String] = []
        if let lowest = summary.lowest { facts.append("Lowest: \(lowest.title)") }
        if let mover = summary.biggestMover {
            facts.append("Biggest move: \(mover.sector.title) \(mover.delta > 0 ? "+" : "")\(mover.delta)")
        }
        return BoardHeadline(eyebrow: eyebrow(month, locale: locale), title: title,
                             detail: facts.isEmpty ? nil : facts.joined(separator: " · "))
    }

    /// In flight: how much of the month is left, and how much is settled.
    public static func inFlight(
        month: Date, remainingDays: Int, meanDecided: Double?, locale: Locale = .current
    ) -> BoardHeadline {
        let title = remainingDays == 1 ? "1 day left" : "\(remainingDays) days left"
        let detail = meanDecided.map { "\(Int(($0 * 100).rounded()))% of this month is decided" }
        return BoardHeadline(eyebrow: eyebrow(month, locale: locale), title: title, detail: detail)
    }

    private static func eyebrow(_ month: Date, locale: Locale) -> String {
        "Life · \(monthName(month, locale: locale))"
    }

    private static func monthName(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale).month(.wide))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter BoardHeadlineTests`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Sectors/BoardHeadline.swift LifeOSKit/Tests/SectorsTests/BoardHeadlineTests.swift
git commit -m "feat(sectors): derive the Life board masthead as a tested value"
```

---

### Task 2: `RoundedBarChart` ink style

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/RoundedBarChart.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/RoundedBarChartTests.swift`

**Interfaces:**
- Produces: `RoundedBarChart.Style` (`.accent`, `.hue(ModuleHue)`, `.ink`), a new `init(bars:style:goal:baseline:spacing:height:)`, and internal `static func barFill(_:scheme:)` / `trackFill(_:scheme:)`. The old `init(bars:hue:...)` keeps working for every existing call site. Tasks 6 and 7 pass `style: .ink`.

- [ ] **Step 1: Add the failing tests** to the existing suite, after the window-minimum tests

```swift
    // MARK: - Styles

    import SwiftUI  // put this with the other imports at the top of the file

    /// Life draws its trends on the dusk field, where the only colours are ink
    /// and the rule.
    @Test func inkStyleDrawsBarsInInkAndTracksAsRules() {
        #expect(Chart.barFill(.ink, scheme: .light) == LifeOSTokens.primaryText.resolve(.light))
        #expect(Chart.barFill(.ink, scheme: .dark) == LifeOSTokens.primaryText.resolve(.dark))
        #expect(Chart.trackFill(.ink, scheme: .light) == Editorial.rule(.light))
    }

    @Test func hueStyleKeepsTheModuleColour() {
        #expect(Chart.barFill(.hue(.activity), scheme: .light) == ModuleHue.activity.top)
        #expect(Chart.trackFill(.hue(.activity), scheme: .dark) == ModuleHue.activity.pastelDark)
    }

    /// Nothing asked for is the accent, as every chart has been so far.
    @Test func accentIsTheDefault() {
        #expect(Chart.barFill(.accent, scheme: .light) == LifeOSTokens.accent)
        #expect(Chart.trackFill(.accent, scheme: .light) == LifeOSTokens.accentSoft.resolve(.light))
    }
```

(Move the `import SwiftUI` line to the file header beside `import Testing`; it is shown inline only so the step is self-contained.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter RoundedBarChartTests`
Expected: compile error, `type 'RoundedBarChart' has no member 'barFill'`.

- [ ] **Step 3: Implement the style**

Replace the `hue` stored property, the two initialisers and the two private fills in `RoundedBarChart.swift` with:

```swift
    /// What colours the bars. The accent is the app-wide default; a module hue
    /// is for the metric screens that still carry one; ink is for a chart on
    /// the editorial dusk field, where the only colours are ink and the rule.
    public enum Style: Sendable, Equatable {
        case accent
        case hue(ModuleHue)
        case ink
    }

    private let bars: [Bar]
    private let style: Style
    private let goal: Double?
    private let baseline: Baseline
    private let spacing: CGFloat
    private let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(
        bars: [Bar],
        style: Style = .accent,
        goal: Double? = nil,
        baseline: Baseline = .zero,
        spacing: CGFloat = 10,
        height: CGFloat = 150
    ) {
        self.bars = bars
        self.style = style
        self.goal = goal
        self.baseline = baseline
        self.spacing = spacing
        self.height = height
    }

    /// The older spelling. `hue` has no default here on purpose: with one,
    /// `RoundedBarChart(bars:)` would match both initialisers.
    public init(
        bars: [Bar],
        hue: ModuleHue?,
        goal: Double? = nil,
        baseline: Baseline = .zero,
        spacing: CGFloat = 10,
        height: CGFloat = 150
    ) {
        self.init(bars: bars, style: hue.map(Style.hue) ?? .accent, goal: goal,
                  baseline: baseline, spacing: spacing, height: height)
    }

    static func barFill(_ style: Style, scheme: ColorScheme) -> Color {
        switch style {
        case .accent: LifeOSTokens.accent
        case .hue(let hue): hue.top
        case .ink: LifeOSTokens.primaryText.resolve(scheme)
        }
    }

    static func trackFill(_ style: Style, scheme: ColorScheme) -> Color {
        switch style {
        case .accent: LifeOSTokens.accentSoft.resolve(scheme)
        case .hue(let hue): scheme == .dark ? hue.pastelDark : hue.pastel
        case .ink: Editorial.rule(scheme)
        }
    }

    private var barFill: Color { Self.barFill(style, scheme: scheme) }
    private var trackFill: Color { Self.trackFill(style, scheme: scheme) }
```

Leave `body`, `fraction(of:in:baseline:)`, `meetsGoal` and the `#Preview` as they are.

- [ ] **Step 4: Run the whole package test suite**

Run: `cd LifeOSKit && swift test`
Expected: all suites pass (1376 before this plan, plus 8 new). Every existing `RoundedBarChart(bars:hue:...)` call still compiles because `hue:` is spelled out at those sites.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/RoundedBarChart.swift LifeOSKit/Tests/DesignSystemTests/RoundedBarChartTests.swift
git commit -m "feat(design): give the bar chart an ink style for the dusk field"
```

---

### Task 3: Shell toolbar with the avatar on every tab

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/ProfileAvatar.swift`
- Delete: `LIfeOS/Components/View/ProfileAvatar.swift`
- Modify: `LifeOSKit/Sources/DesignSystem/QuickActionsToolbar.swift`
- Modify: `LifeOSKit/Sources/DesignSystem/ActionFan.swift:189-215` (the `button(_:onTap:)` function)
- Modify: `LIfeOS/App/RootView.swift:234` (environment), `:414-431` (Today bar), `:463`, `:481` (Health and Money), `:532-536` (LIFO action)
- Modify: `LIfeOS/Features/Notes/View/NotesHubScreen.swift:252-262` and `:312-324`
- Modify: `LIfeOS/Features/Life/View/LifeBoardScreen.swift:65`

**Interfaces:**
- Produces: `public struct ShellProfile { photo: Data?; open: () -> Void }`, `EnvironmentValues.shellProfile: ShellProfile?`, `View.shellToolbar()`. `quickActionsToolbar()` stays as a deprecated alias. `ProfileAvatar(photo:size:)` is now public in `DesignSystem`.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Move `ProfileAvatar` into the package**

Create `LifeOSKit/Sources/DesignSystem/ProfileAvatar.swift`:

```swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The signed-in person, as a small circle. Shared by the shell bar and the
/// social screens, so it lives in the package rather than beside one of them.
public struct ProfileAvatar: View {
    public let photo: Data?
    public var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    public init(photo: Data?, size: CGFloat = 30) {
        self.photo = photo; self.size = size
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(LifeOSTokens.dotOutline.resolve(scheme), lineWidth: 1) }
    }

    private var placeholder: some View {
        LifeOSTokens.cardSurface.resolve(scheme)
            .overlay {
                Image(systemName: "person.fill")
                    .font(LifeOSType.label)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
    }
}
```

Then delete the app copy:

```bash
git rm LIfeOS/Components/View/ProfileAvatar.swift
```

`LIfeOS/Features/Social/View/SocialStyle.swift:53` already imports `DesignSystem` and calls `ProfileAvatar(photo:size:)`, so it needs no edit. (The old file drew the glyph at `size * 0.45`; the scale forbids computed point sizes only for words, but `LifeOSType.label` at 13pt is what a 30pt circle wants, and it keeps the guard quiet.)

- [ ] **Step 2: Add `ShellProfile` and `ShellToolbar`**

Replace the contents of `LifeOSKit/Sources/DesignSystem/QuickActionsToolbar.swift` with:

```swift
import SwiftUI

/// The app's actions, injected once at the composition root so any screen can
/// put them in its own navigation bar.
///
/// An environment value rather than a parameter because the screens that need
/// them are not all reachable from one place: Notes and Life own their own
/// `NavigationStack`s several levels below `RootView`, and a toolbar has to be
/// attached inside the stack it belongs to.
public extension EnvironmentValues {
    /// Empty by default, so a screen rendered in a preview without the shell's
    /// injection draws no bar rather than crashing for want of one.
    @Entry var quickActions: [QuickAction] = []
    /// Who is signed in. Nil draws no avatar, for the same reason.
    @Entry var shellProfile: ShellProfile? = nil
}

/// The signed-in person for the bar: their photo, and what the avatar opens.
public struct ShellProfile {
    public let photo: Data?
    public let open: () -> Void

    public init(photo: Data?, open: @escaping () -> Void) {
        self.photo = photo; self.open = open
    }
}

/// The one header every tab carries: the actions, then the avatar outermost.
///
/// `.primaryAction` rather than `.topBarTrailing`: the placement resolves to
/// the trailing edge on iOS and the package still builds for macOS, which has
/// no top bar to name. Items keep declaration order, so the avatar, declared
/// last, sits at the edge.
public struct ShellToolbar: ViewModifier {
    @Environment(\.quickActions) private var actions
    @Environment(\.shellProfile) private var profile
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public func body(content: Content) -> some View {
        paper(content)
            .toolbar {
                if !actions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ActionFan(actions: actions, arrangement: .row)
                    }
                }
                if let profile {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: profile.open) { ProfileAvatar(photo: profile.photo) }
                            .accessibilityLabel("Profile and settings")
                    }
                }
            }
    }

    /// The bar is paper, not system material: a translucent bar over a
    /// masthead reads as a second, blurrier masthead.
    @ViewBuilder private func paper(_ content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(LifeOSTokens.canvas.resolve(scheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        content
        #endif
    }
}

public extension View {
    /// The app's header across the top of this screen. Every tab calls this.
    func shellToolbar() -> some View {
        modifier(ShellToolbar())
    }

    @available(*, deprecated, renamed: "shellToolbar")
    func quickActionsToolbar() -> some View {
        modifier(ShellToolbar())
    }
}
```

- [ ] **Step 3: Draw a labelled non-prominent action as a word pill**

In `ActionFan.swift`, inside `button(_:onTap:)`, the label currently has two branches (`if filled, let word = action.shortLabel` and `else`). Insert a middle branch so it reads:

```swift
            if filled, let word = action.shortLabel {
                // (unchanged ink capsule)
                Label(word, systemImage: action.systemImage)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.fabGlyph.resolve(scheme))
                    .padding(.horizontal, 12)
                    .frame(height: size)
                    .background(Capsule().fill(LifeOSTokens.fabFill.resolve(scheme)))
            } else if arrangement == .row, let word = action.shortLabel {
                // A named action that is not the prominent one: an outlined
                // word, the way EditorialTag draws an outlined word, so LIFO
                // reads as LIFO rather than as a speech-bubble guess.
                Text(word)
                    .font(LifeOSType.label.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.horizontal, 12)
                    .frame(height: size)
                    .overlay(Capsule().strokeBorder(LifeOSTokens.primaryText.resolve(scheme).opacity(0.5), lineWidth: 1))
            } else {
                // (unchanged glyph branch)
```

- [ ] **Step 4: Wire `RootView`**

At line 234, after `.environment(\.quickActions, quickActions)`, add:

```swift
        .environment(\.shellProfile, ShellProfile(photo: profilePhoto, open: { showSettings = true }))
```

In the `.today` case (lines 414-431): change `.quickActionsToolbar()` to `.shellToolbar()` and delete the whole `ToolbarItem(placement: .topBarTrailing) { ... ProfileAvatar ... }` block, leaving only the leading calendar item inside `.toolbar { }`. In the `.health` and `.money` cases change `.quickActionsToolbar()` to `.shellToolbar()`.

In `quickActions` (line 532) give LIFO its word:

```swift
            QuickAction(id: "coach", systemImage: "message.fill", label: "LIFO", shortLabel: "LIFO") {
                showCoach = true
            },
```

- [ ] **Step 5: Notes and Life**

`NotesHubScreen.swift`, `compactShell` (line 252): delete the `.navigationTitle("Notes")` line. In `shelf` (line 312) add the bar after the display-mode modifier:

```swift
        .navigationBarTitleDisplayMode(.inline)
        .shellToolbar()
```

`LifeBoardScreen.swift:65`: `.quickActionsToolbar()` becomes `.shellToolbar()`.

- [ ] **Step 6: Build the package and the app**

Run: `cd LifeOSKit && swift test` then from the worktree root
`xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet`
Expected: tests pass; the app builds with zero errors. `grep -c 'ProfileAvatar(' LIfeOS/App/RootView.swift` prints `0`.

- [ ] **Step 7: Commit**

```bash
git add -A LifeOSKit/Sources/DesignSystem LIfeOS/App/RootView.swift LIfeOS/Features/Notes/View/NotesHubScreen.swift LIfeOS/Features/Life/View/LifeBoardScreen.swift LIfeOS/Components
git commit -m "feat(shell): one header with the avatar on every tab

The avatar used to sit on Today alone and Notes carried a system title
beside three bare glyphs. Every tab now draws the same bar from the
environment: assistant, LIFO as a word, Start, then the avatar, on paper."
```

---

### Task 4: `EditorialEmptyState`

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/EditorialEmptyState.swift`

**Interfaces:**
- Produces: `EditorialEmptyState(sentence:action:onAction:sample:)`. Task 5 uses it; later PRs reuse it for Today, Notes, Health and Money.

- [ ] **Step 1: Write the component**

```swift
import SwiftUI

/// A tab with nothing in it yet, shown as a ghost of what it will hold.
///
/// The sample is drawn by the caller at 35% ink with hit testing off and is
/// hidden from VoiceOver: it teaches by shape, not by content. One sentence
/// says what the tab shows, one button is the action that fills it.
public struct EditorialEmptyState<Sample: View>: View {
    let sentence: String
    let action: String
    let onAction: () -> Void
    let sample: Sample
    @Environment(\.colorScheme) private var scheme

    public init(sentence: String, action: String, onAction: @escaping () -> Void,
                @ViewBuilder sample: () -> Sample) {
        self.sentence = sentence; self.action = action; self.onAction = onAction
        self.sample = sample()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Sample").editorialEyebrow()
            sample
                .opacity(0.35)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Text(sentence)
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAction) { Text(action) }
                .buttonStyle(.editorial(.primary))
        }
        .editorialCard()
    }
}
```

- [ ] **Step 2: Build the package**

Run: `cd LifeOSKit && swift build`
Expected: builds. (A view with no logic gets no unit test; Task 10's `life-empty` page is its check.)

- [ ] **Step 3: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/EditorialEmptyState.swift
git commit -m "feat(design): add the teaching empty state"
```

---

### Task 5: Life board masthead, mode switch, banner, empty state

**Files:**
- Modify: `LIfeOS/Features/Life/ViewModel/LifeBoardViewModel.swift`
- Modify: `LIfeOS/Features/Life/View/LifeBoardScreen.swift`
- Modify: `LIfeOS/Features/Life/View/CloseBanner.swift`

**Interfaces:**
- Consumes: `BoardHeadline` (Task 1), `EditorialEmptyState` (Task 4), `UnderlinePicker(selection:options:)`.
- Produces: `LifeBoardViewModel.headline: BoardHeadline`, `LifeBoardViewModel.isBlank: Bool`, `LifeBoardViewModel.month: Date`, `lastClosedMonth: Date?`. Task 6 provides `SectorBandRow`, which this task's empty state draws; until Task 6 lands, the sample uses plain text rows (see Step 3) and Task 6 swaps them.

- [ ] **Step 1: Extend the view model**

In `LifeBoardViewModel.swift`:

Change the mode default and add the two dates after `monthAwaitingClose`:

```swift
    private(set) var monthAwaitingClose: Date?
    /// The month the board is looking at, for the masthead.
    private(set) var month: Date = .now
    /// The month the last close belongs to, or nil when nothing was ever closed.
    private(set) var lastClosedMonth: Date?
    /// Opens on the month in progress: it is the mode with something to do.
    var mode: BoardMode = .inFlight {
        didSet { if mode != oldValue { load() } }
    }
```

Add after `meanDecided`:

```swift
    var headline: BoardHeadline {
        switch mode {
        case .closed:
            BoardHeadline.closed(month: month, lastClosed: lastClosedMonth, summary: summary)
        case .inFlight:
            BoardHeadline.inFlight(month: month, remainingDays: progress?.remainingDays ?? 0,
                                   meanDecided: meanDecided)
        }
    }

    /// Nothing closed and nothing read: the deck would be nine dashes.
    var isBlank: Bool {
        lastClosedMonth == nil && cards.allSatisfy { $0.score == nil && $0.band?.floor == nil }
    }
```

In `load(now:)`, after `let previous = scoreMap(...)`, record the two dates:

```swift
        month = thisMonth
        lastClosedMonth = current.isEmpty ? nil : lastMonth
```

Also swap the two `BoardMode.title` strings so the picker reads as the spec wants: `.closed` is `"Last close"`, `.inFlight` is `"This month"`.

- [ ] **Step 2: Rebuild the board screen**

Replace the `body`'s inner `VStack` and the `header` property in `LifeBoardScreen.swift`:

```swift
                VStack(alignment: .leading, spacing: Space.x3) {
                    EditorialMasthead(eyebrow: model.headline.eyebrow,
                                      title: model.headline.title,
                                      detail: model.headline.detail)

                    UnderlinePicker(
                        selection: Binding(get: { model.mode }, set: { model.mode = $0 }),
                        options: [(.inFlight, LifeBoardViewModel.BoardMode.inFlight.title),
                                  (.closed, LifeBoardViewModel.BoardMode.closed.title)]
                    )

                    if let month = model.monthAwaitingClose {
                        CloseBanner(month: month) {
                            closeMonth = month
                            showClose = true
                        }
                    }

                    if model.isBlank {
                        emptyState
                    } else {
                        SectorStack(cards: model.cards) { sector in
                            openSector = sector
                        }
                    }
                }
```

Delete the `header` property and the `Picker` entirely. Add the empty state:

```swift
    /// The board before anything is on it: a ghost of three bands and the one
    /// thing to do.
    private var emptyState: some View {
        EditorialEmptyState(
            sentence: "Nine sectors, scored once a month. The board shows where life stands.",
            action: "Score this month",
            onAction: {
                closeMonth = model.monthAwaitingClose ?? model.month
                showClose = true
            }
        ) {
            VStack(spacing: Space.x1) {
                SectorBandRow(index: 1, title: "Family", value: "7", unit: "/10", isOpen: false)
                SectorBandRow(index: 2, title: "Body", value: "8", unit: "/10", isOpen: false)
                SectorBandRow(index: 3, title: "Money", value: "6", unit: "/10", isOpen: false)
            }
        }
    }
```

`SectorBandRow` arrives in Task 6. To keep this task building on its own, Task 6 is implemented straight after; if you must build between them, use `Text("01  Family  7/10")` rows for the sample and replace them in Task 6.

- [ ] **Step 3: Make the close banner an editorial card**

In `CloseBanner.swift`, replace the trailing modifiers on the outer `VStack` (`.padding(Space.x2)` through the dashed `.overlay(...)`) with:

```swift
        .editorialCard()
```

and change the `Score now` button to the house style:

```swift
                Button("Score now", action: onScore)
                    .buttonStyle(.editorial(.primary, size: .compact))
```

(delete its old label closure, `.foregroundStyle`, padding, capsule overlay and `.buttonStyle(.plain)`).

- [ ] **Step 4: Build**

Run the app build from Task 3 Step 6 after Task 6 is also in place.
Expected: zero errors.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Life/ViewModel/LifeBoardViewModel.swift LIfeOS/Features/Life/View/LifeBoardScreen.swift LIfeOS/Features/Life/View/CloseBanner.swift
git commit -m "feat(life): masthead, underline modes and a teaching empty state on the board"
```

---

### Task 6: The deck on paper

**Files:**
- Modify: `LIfeOS/Features/Life/View/SectorStack.swift`

**Interfaces:**
- Consumes: `RoundedBarChart(bars:style:...)` with `.ink` (Task 2), `EditorialFieldTone.dusk`, `Editorial.index/figure/headline/quietInk/rule`.
- Produces: `struct SectorBandRow: View` with `init(index:title:value:unit:isOpen:)`, used by Task 5's empty state.

- [ ] **Step 1: Replace `SectorDeckCard` and add `SectorBandRow`**

Keep `SectorStack` (the `VStack` with negative spacing, `peek`, `closedHeight`, `openHeight`, `toggle`) exactly as it is, except pass the index through:

```swift
                SectorDeckCard(
                    index: index + 1,
                    card: card,
                    peek: Self.peek,
                    height: isOpen ? Self.openHeight(for: card) : Self.closedHeight,
                    isOpen: isOpen,
                    onOpenDetail: { onOpenDetail(card.sector) }
                )
```

Replace everything from `/// One card in the deck.` to the end of the file with:

```swift
/// The band that survives being covered: index, sector, score, and the
/// chevron that says it opens.
///
/// Shared with the board's teaching empty state, which ghosts three of these.
struct SectorBandRow: View {
    let index: Int
    let title: String
    let value: String
    let unit: String?
    let isOpen: Bool
    /// Nil draws in the paper ink; the open card passes the dusk field's ink.
    var ink: Color? = nil
    var hasValue = true

    @Environment(\.colorScheme) private var scheme

    private var primary: Color { ink ?? LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { ink.map { $0.opacity(0.6) } ?? Editorial.quietInk(scheme) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Text(Editorial.index(index))
                .font(LifeOSType.label.monospacedDigit())
                .foregroundStyle(quiet)
                .accessibilityHidden(true)
            Text(title)
                .font(Editorial.headline(22)).tracking(-0.4)
                .foregroundStyle(primary)
            Spacer(minLength: Space.x1)
            HStack(alignment: .firstTextBaseline, spacing: Space.half) {
                Text(value)
                    .font(Editorial.figure(28)).tracking(Editorial.figureTracking(28))
                    .monospacedDigit()
                    .foregroundStyle(hasValue ? primary : quiet)
                if let unit {
                    Text(unit).font(LifeOSType.caption).foregroundStyle(quiet)
                }
            }
            Image(systemName: "chevron.down")
                .font(LifeOSType.caption.weight(.semibold))
                .foregroundStyle(quiet)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .accessibilityHidden(true)
        }
    }
}

/// One card in the deck.
///
/// Closed, it is paper with a hairline edge and only its band showing.
/// Open, it is the screen's one dusk field, carrying the trend in ink.
private struct SectorDeckCard: View {
    let index: Int
    let card: LifeBoardViewModel.Card
    let peek: CGFloat
    let height: CGFloat
    let isOpen: Bool
    let onOpenDetail: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var fieldInk: Color { EditorialFieldTone.dusk.ink(scheme) }
    private var radius: CGFloat { Radius.medium + 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            SectorBandRow(index: index, title: card.sector.title, value: scoreText, unit: scoreUnit,
                          isOpen: isOpen, ink: isOpen ? fieldInk : nil, hasValue: hasValue)
                .frame(height: peek - Space.x2 - Space.x1, alignment: .center)

            // Nothing renders below the band while closed: a covered card has
            // only `peek` points of room.
            if isOpen { openBody }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.x2)
        .padding(.vertical, Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background {
            if isOpen {
                LinearGradient(colors: EditorialFieldTone.dusk.colors(scheme), startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            }
        }
        .overlay {
            if !isOpen {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Editorial.rule(scheme))
            }
        }
        .accessibilityElement(children: isOpen ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "Collapse" : "Expand for the trend")
    }

    @ViewBuilder
    private var openBody: some View {
        Text(trendLine)
            .font(LifeOSType.secondary.weight(.medium))
            .foregroundStyle(fieldInk.opacity(0.7))

        if card.history.count > 1 {
            RoundedBarChart(
                bars: card.history.map {
                    RoundedBarChart.Bar(
                        id: $0.id,
                        label: $0.id.formatted(.dateTime.month(.narrow)),
                        value: $0.value
                    )
                },
                style: .ink,
                spacing: Space.half,
                height: 64
            )
        }

        Spacer(minLength: 0)

        Button(action: onOpenDetail) {
            HStack(spacing: Space.half) {
                Text("Open \(card.sector.title)")
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
    }

    private var scoreText: String {
        if let band = card.band {
            return band.rangeText ?? "—"
        }
        return card.score.map(String.init) ?? "—"
    }

    private var scoreUnit: String? {
        card.band == nil && card.score != nil ? "/10" : nil
    }

    private var hasValue: Bool {
        card.band.map { $0.floor != nil } ?? (card.score != nil)
    }

    private var trendLine: String {
        if let band = card.band {
            guard band.floor != nil else { return "Not read yet" }
            guard let decided = band.decided else { return "No ceiling without budgets" }
            return "\(Int((decided * 100).rounded()))% decided"
        }
        guard card.score != nil else { return "Not scored yet" }
        guard card.history.count > 1 else { return "First month scored" }
        let months = card.history.suffix(2)
        guard let previous = months.first?.value, let latest = months.last?.value else {
            return " "
        }
        let delta = latest - previous
        if delta == 0 { return "Level with last month" }
        return "\(delta > 0 ? "Up" : "Down") \(abs(delta)) from last month"
    }

    private var accessibilityText: String {
        if let band = card.band {
            guard let floor = band.floor else { return "\(card.sector.title), not read yet" }
            guard let ceiling = band.ceiling, ceiling != floor else {
                return "\(card.sector.title), closing at \(floor)"
            }
            return "\(card.sector.title), between \(floor) and \(ceiling)"
        }
        let score = card.score.map { "score \($0)" } ?? "not scored yet"
        return "\(card.sector.title), \(score)"
    }
}
```

The old `fill` gradient, `ink` and `band` members are gone with this replacement. `abs(delta)` on a `Double` prints `2.0`; keep the existing behaviour (it was already a `Double` there) but format it: replace `abs(delta)` with `Int(abs(delta))`.

- [ ] **Step 2: Build**

Run the app build (Task 3 Step 6 command).
Expected: zero errors. `grep -n 'SectorPalette.tone\|cardInk' LIfeOS/Features/Life/View/SectorStack.swift` prints nothing.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Life/View/SectorStack.swift
git commit -m "feat(life): draw the deck on paper with an index, a chevron and one dusk field"
```

---

### Task 7: Sector detail on numbered sections

**Files:**
- Modify: `LIfeOS/Features/Life/View/SectorDetailScreen.swift`

**Interfaces:**
- Consumes: `EditorialField`, `EditorialFigure`, `EditorialSectionHeader`, `EditorialRow`, `Hairline`, `RoundedBarChart(style: .ink)`.

- [ ] **Step 1: Replace the bands**

Replace the `body`'s inner `VStack` content and every function from `// MARK: - Bands` to the end of the struct with:

```swift
                if let history = model.history {
                    header(history)
                    if history.months.isEmpty { emptyState }
                    ForEach(Array(sections(history).enumerated()), id: \.element) { offset, section in
                        VStack(alignment: .leading, spacing: Space.x2) {
                            EditorialSectionHeader(index: offset + 1, title: section.title)
                            content(section, history: history)
                        }
                    }
                    if let onOpenTab { openTabRow(onOpenTab) }
                } else {
                    ProgressView()
                }
```

and:

```swift
    // MARK: - Sections

    /// The bands in order, only those with something to show, so the index
    /// numbers run without gaps.
    private enum Section: Hashable {
        case observations, trend, reasoning, answers, notes

        var title: String {
            switch self {
            case .observations: "Observations"
            case .trend: "Trend"
            case .reasoning: "Why"
            case .answers: "Answers over time"
            case .notes: "Notes"
            }
        }
    }

    private func sections(_ history: SectorHistory) -> [Section] {
        var list: [Section] = []
        if !history.observations.isEmpty { list.append(.observations) }
        if !history.months.isEmpty { list.append(.trend) }
        if let latest = history.months.last, !latest.evidenceRows.isEmpty { list.append(.reasoning) }
        if !visibleTracks(history).isEmpty { list.append(.answers) }
        if !history.notes.isEmpty { list.append(.notes) }
        return list
    }

    @ViewBuilder
    private func content(_ section: Section, history: SectorHistory) -> some View {
        switch section {
        case .observations:
            ForEach(history.observations, id: \.self) { observation in
                Text(observation).font(LifeOSType.secondary)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
        case .trend:
            trend(history)
        case .reasoning:
            if let latest = history.months.last {
                Text("Why \(latest.month.formatted(.dateTime.month(.wide)))").editorialEyebrow()
                ForEach(latest.evidenceRows, id: \.label) { row in
                    EditorialRow(row.label, value: row.value)
                }
            }
        case .answers:
            ForEach(visibleTracks(history), id: \.questionID) { track in
                questionTrackRow(track, months: history.months)
            }
        case .notes:
            ForEach(Array(history.notes.enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: Space.half) {
                    Text(note.month.formatted(.dateTime.month(.wide).year())).editorialEyebrow()
                    Text(note.text).font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    Hairline()
                }
            }
        }
    }

    /// The screen's one field: the score, the month it belongs to, the icon.
    private func header(_ history: SectorHistory) -> some View {
        let latest = history.months.last
        return EditorialField(.dusk) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(latest.map { "\(sector.title) · \($0.month.formatted(.dateTime.month(.wide).year()))" } ?? sector.title)
                        .editorialEyebrow()
                    EditorialFigure(label: "Score",
                                    value: latest.map { String($0.userScore) } ?? "—",
                                    unit: latest == nil ? nil : "/10")
                }
                Spacer(minLength: Space.x1)
                Image(systemName: SectorPalette.icon(sector))
                    .font(LifeOSType.sectionTitle)
                    .accessibilityHidden(true)
            }
        }
    }

    private var emptyState: some View {
        Text("Close a month on the board to start this sector's history.")
            .font(LifeOSType.secondary)
            .editorialCard()
    }

    /// `baseline: .windowMinimum`, not `.zero`: a sector score is a rating on
    /// a 0...10 scale, never a count building up from nought. The absolute
    /// value is carried by the header figure, not by bar height.
    private func trend(_ history: SectorHistory) -> some View {
        RoundedBarChart(
            bars: history.months.map {
                RoundedBarChart.Bar(
                    id: $0.month,
                    label: $0.month.formatted(.dateTime.month(.narrow)),
                    value: Double($0.userScore)
                )
            },
            style: .ink,
            baseline: .windowMinimum,
            height: 120
        )
    }

    private func visibleTracks(_ history: SectorHistory) -> [QuestionTrack] {
        history.questions.filter { $0.hasAnswer(inLastMonths: answerWindow) }
    }

    private func questionTrackRow(_ track: QuestionTrack, months: [MonthEntry]) -> some View {
        let entries: [MonthAnswer] = Array(zip(months, track.answers).suffix(answerWindow))
            .map { MonthAnswer(month: $0.0.month, answer: $0.1) }
        return VStack(alignment: .leading, spacing: Space.half) {
            Text(track.prompt).font(LifeOSType.label.weight(.regular))
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(entries) { entry in
                        VStack(spacing: Space.half) {
                            Text(entry.month.formatted(.dateTime.month(.narrow))).editorialEyebrow()
                            Text(entry.answer ?? "—").font(LifeOSType.secondary)
                                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        }
                    }
                }
            }
            Hairline()
        }
    }

    private struct MonthAnswer: Identifiable {
        let month: Date
        let answer: String?
        var id: Date { month }
    }

    private func openTabRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("Open \(sector.title)")
                Spacer()
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(.editorial(.secondary, fullWidth: true))
    }
```

Keep the `.navigationTitle(sector.title)` on the pushed screen: pushed screens keep inline titles.

- [ ] **Step 2: Build**

Run the app build.
Expected: zero errors. `grep -c 'PastelFillCard\|SoftCard' LIfeOS/Features/Life/View/SectorDetailScreen.swift` prints `0`.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Life/View/SectorDetailScreen.swift
git commit -m "feat(life): sector detail as one field and numbered sections"
```

---

### Task 8: In-flight sector on a masthead

**Files:**
- Modify: `LIfeOS/Features/Life/View/InFlightSectorScreen.swift`

- [ ] **Step 1: Replace the header and sections**

Replace the `body`'s inner `VStack` content with:

```swift
                EditorialMasthead(eyebrow: "\(sector.title) · In flight",
                                  title: rangeText,
                                  detail: model.remainingDays == 1 ? "1 day left" : "\(model.remainingDays) days left")

                if model.band?.ceiling == nil, sector == .money {
                    Text("No ceiling until you set budget buckets. Nothing in the data says what a good remaining spend would be.")
                        .font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }

                ForEach(Array(sections.enumerated()), id: \.element) { offset, section in
                    VStack(alignment: .leading, spacing: Space.x2) {
                        EditorialSectionHeader(index: offset + 1, title: section.title)
                        content(section)
                    }
                }

                if model.usesDefaultTargets {
                    Text("This ceiling uses the default targets. Set your own in Health to make it yours.")
                        .font(LifeOSType.caption)
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
```

Delete `bandHeader`, `section(_:content:)` and `evidenceRows`, and add:

```swift
    private enum Section: Hashable {
        case levers, questions, floor, ceiling

        var title: String {
            switch self {
            case .levers: "What moves it most"
            case .questions: "Read it now"
            case .floor: "If nothing changes"
            case .ceiling: "If you finish at your targets"
            }
        }
    }

    private var sections: [Section] {
        var list: [Section] = []
        if !model.levers.isEmpty { list.append(.levers) }
        if !model.questions.isEmpty { list.append(.questions) }
        if let band = model.band, !band.floorEvidence.isEmpty {
            list.append(.floor)
            if band.ceiling != nil { list.append(.ceiling) }
        }
        return list
    }

    @ViewBuilder
    private func content(_ section: Section) -> some View {
        switch section {
        case .levers:
            ForEach(model.levers) { delta in
                EditorialRow(delta.lever.label,
                             value: delta.delta < 0.05 ? "at target" : "+\(delta.delta.formatted(.number.precision(.fractionLength(1))))")
            }
        case .questions:
            ForEach(model.questions, id: \.id) { question in
                CheckInQuestionView(
                    question: question,
                    answer: model.answers[question.id],
                    onAnswer: { model.answer(question, with: $0) }
                )
            }
        case .floor:
            if let band = model.band { evidenceRows(band.floorEvidence) }
        case .ceiling:
            if let band = model.band { evidenceRows(band.ceilingEvidence) }
        }
    }

    @ViewBuilder
    private func evidenceRows(_ evidence: Evidence) -> some View {
        ForEach(evidence.rows, id: \.label) { row in
            EditorialRow(row.label, value: row.value)
        }
    }
```

Keep `rangeText`, `.background`, `.navigationTitle`, `.onAppear` and `.onDisappear`.

- [ ] **Step 2: Build**

Run the app build.
Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Life/View/InFlightSectorScreen.swift
git commit -m "feat(life): in-flight sector as a masthead and numbered sections"
```

---

### Task 9: Monthly close on the theme, palette cleanup

**Files:**
- Modify: `LIfeOS/Features/Life/View/MonthlyCloseScreen.swift`
- Modify: `LIfeOS/Features/Life/View/SectorPalette.swift`

- [ ] **Step 1: Replace the header, proposed card and done view**

In `sectorView(_:model:)`:

- Replace `header(sector)` with
  ```swift
                  EditorialMasthead(eyebrow: "Close \(monthName) · \(model.position) of \(model.total)",
                                    title: sector.title)
  ```
  and add `private var monthName: String { month.formatted(.dateTime.month(.wide)) }` to the struct.
- Replace the `PastelFillCard(...)` call and the evidence `VStack` that follows it with:
  ```swift
                  VStack(alignment: .leading, spacing: Space.x2) {
                      EditorialFigure(label: "Proposed",
                                      value: model.proposed.map(String.init) ?? "—",
                                      unit: model.proposed == nil ? nil : "/10",
                                      size: 48)
                      if model.evidence.rows.isEmpty {
                          EditorialTag("No evidence yet")
                      } else {
                          ForEach(model.evidence.rows, id: \.label) { row in
                              EditorialRow(row.label.capitalized, value: row.value)
                          }
                      }
                  }
                  .editorialCard()
  ```
- Replace `.navigationTitle("\(model.position) of \(model.total)")` with `.navigationTitle("")` (the masthead carries it; the bar keeps Skip and Next).
- Delete the `header(_:)` function.

Replace `doneView` with:

```swift
    private var doneView: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            EditorialMasthead(eyebrow: "Life",
                              title: "Month closed",
                              detail: "Every sector you scored this pass is on the board.")
            Button("Done") {
                onFinish()
                dismiss()
            }
            .buttonStyle(.editorial(.primary, fullWidth: true))
            Spacer()
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
    }
```

- [ ] **Step 2: Retire the sector palette**

Replace the whole of `SectorPalette.swift` with:

```swift
import SwiftUI
import Persistence

/// The one place a sector meets an icon.
///
/// Kept out of `LifeSector` so the Persistence target never imports SwiftUI
/// or DesignSystem. The sectors used to carry colours too; the editorial
/// theme draws every one of them in ink on paper, so only the icon is left.
enum SectorPalette {
    static func icon(_ sector: LifeSector) -> String {
        switch sector {
        case .family:  "house.fill"
        case .romance: "heart.fill"
        case .soul:    "sparkles"
        case .friends: "person.2.fill"
        case .growth:  "chart.line.uptrend.xyaxis"
        case .money:   "dollarsign"
        case .mission: "target"
        case .body:    "figure.run"
        case .mind:    "brain.head.profile"
        }
    }
}
```

- [ ] **Step 3: Build and check nothing else used the palette**

Run: `grep -rn 'SectorPalette\.\(hue\|tone\|cardInk\)' LIfeOS` then the app build.
Expected: no matches; zero errors.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Life/View/MonthlyCloseScreen.swift LIfeOS/Features/Life/View/SectorPalette.swift
git commit -m "feat(life): monthly close on the theme, retire the sector tones"
```

---

### Task 10: Preview pages and the screenshot review

**Files:**
- Create: `LIfeOS/Features/Life/View/LifeDesignPreview.swift`
- Modify: `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:97-98` (the page routing)

**Interfaces:**
- Consumes: every screen above; `LifeOSContainer.make(inMemory:)`, `SectorStore.record(sector:month:proposed:evidence:)`, `SectorStore.commit(userScore:to:)`, `EvidenceRow(label:value:normalised:)`, `Evidence(_:)`.

- [ ] **Step 1: Write the preview and its fixture**

```swift
// LIfeOS/Features/Life/View/LifeDesignPreview.swift
#if DEBUG
import SwiftUI
import SwiftData
import DesignSystem
import Persistence
import Sectors

/// Fixture pages for the Life tab and the shell header, mounted by
/// `--design-preview` with `--page=life`, `life-empty`, `life-detail`,
/// `life-inflight`, `life-close` or `shell`. Six closed months are invented
/// in an in-memory store; nothing here touches the real one.
struct LifeDesignPreview: View {
    let page: String
    @State private var fixture = LifeFixture()

    var body: some View {
        Group {
            switch page {
            case "life-empty":
                LifeBoardScreen(model: fixture.emptyBoard, onOpenTab: { _ in })
                    .modelContainer(fixture.emptyContainer)
            case "life-detail":
                NavigationStack { SectorDetailScreen(sector: .body, onOpenTab: {}) }
                    .modelContainer(fixture.container)
            case "life-inflight":
                NavigationStack { InFlightSectorScreen(sector: .body) }
                    .modelContainer(fixture.container)
            case "life-close":
                MonthlyCloseScreen(month: fixture.lastMonth)
                    .modelContainer(fixture.container)
            case "shell":
                shell
            default:
                LifeBoardScreen(model: fixture.board, onOpenTab: { _ in })
                    .modelContainer(fixture.container)
            }
        }
        .environment(\.quickActions, Self.actions)
        .environment(\.shellProfile, ShellProfile(photo: nil, open: {}))
    }

    /// A paper page under the full header, to look at the bar on its own.
    private var shell: some View {
        NavigationStack {
            ScrollView {
                EditorialMasthead(eyebrow: "Shell · Preview", title: "The header",
                                  detail: "Assistant, LIFO, Start, then you.")
                    .padding(Space.x3)
            }
            .background(LifeOSTokens.canvas.resolve(.light).ignoresSafeArea())
            .shellToolbar()
        }
    }

    static let actions: [QuickAction] = [
        QuickAction(id: "assistant", systemImage: "calendar.badge.clock", label: "Calendar assistant") {},
        QuickAction(id: "coach", systemImage: "message.fill", label: "LIFO", shortLabel: "LIFO") {},
        QuickAction(id: "beginActivity", systemImage: "plus", label: "Begin activity", isProminent: true, shortLabel: "Start") {},
    ]
}

@MainActor private final class LifeFixture {
    let container = try! LifeOSContainer.make(inMemory: true)
    let emptyContainer = try! LifeOSContainer.make(inMemory: true)
    let board = LifeBoardViewModel()
    let emptyBoard = LifeBoardViewModel()
    let calendar = Calendar.current
    let lastMonth: Date

    init() {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))!
        lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
        seed(thisMonth: thisMonth)
        board.attach(container.mainContext)
        board.load()
        emptyBoard.attach(emptyContainer.mainContext)
        emptyBoard.load()
    }

    /// Six closed months per sector, with a shape in each so the trend has
    /// something to say: Body climbs, Friends dips, the rest wander.
    private func seed(thisMonth: Date) {
        let store = SectorStore(context: container.mainContext, calendar: calendar)
        let shapes: [LifeSector: [Int]] = [
            .family: [6, 6, 7, 7, 7, 8], .romance: [5, 6, 6, 7, 6, 7], .soul: [4, 5, 5, 6, 6, 6],
            .friends: [7, 7, 6, 5, 4, 3], .growth: [6, 6, 6, 7, 8, 8], .money: [5, 6, 6, 6, 7, 6],
            .mission: [6, 7, 7, 8, 8, 8], .body: [4, 5, 6, 6, 7, 8], .mind: [6, 5, 6, 6, 7, 7],
        ]
        for (sector, scores) in shapes {
            for (offset, value) in scores.enumerated() {
                let month = calendar.date(byAdding: .month, value: offset - scores.count, to: thisMonth)!
                let evidence = Evidence([
                    EvidenceRow(label: "Sleep", value: "7h 12m", normalised: 0.8),
                    EvidenceRow(label: "Exercise", value: "4 of 5 sessions", normalised: 0.8),
                ])
                let score = try! store.record(sector: sector, month: month, proposed: value, evidence: evidence)
                try! store.commit(userScore: value, to: score)
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Route the pages**

In `HealthActivityDesignPreview.swift`, change the money/nav line to:

```swift
            else if page == "money" || page == "nav" { EditorialDesignPreview(page: page) }
            else if page.hasPrefix("life") || page == "shell" { LifeDesignPreview(page: page) }
```

- [ ] **Step 3: Build, install, and capture every page in light and dark**

From the worktree root (the booted simulator is `780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4`, iPhone 17):

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4' -quiet
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q editorial-shell "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done)
SIM=780ECD75-4EE2-4EA4-AACE-E4F8C1D96CB4
xcrun simctl install $SIM "$APP"
for page in shell life life-empty life-detail life-inflight life-close; do
  for mode in "" "--dark"; do
    xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
    xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview --page=$page $mode >/dev/null
    perl -e 'select(undef,undef,undef,4)'
    xcrun simctl io $SIM screenshot "/private/tmp/claude-501/-Users-shivvyas-LIfeOS/540be88d-a1c8-4704-b181-241ac1f7aebf/scratchpad/pr1-$page$mode.png" >/dev/null
  done
done
```

Then open each PNG and check against the spec:
- `shell`: bar is paper; trailing order is assistant glyph, outlined `LIFO`, ink `Start`, avatar circle.
- `life`: masthead eyebrow `LIFE · <MONTH>`, headline `<N> days left`, underline tabs `This month | Last close`, deck of paper cards with `01`…`09`, chevrons, light figures. Tap the first band (use `cliclick` per the simulator memory note) and confirm the open card is the dusk gradient with ink bars and an outlined `Open Family` button.
- `life-empty`: a ghosted three-band sample, the sentence, and the ink `Score this month` button.
- `life-detail`: dusk field with `Score 8 /10`, then `01 Trend`, `02 Why <Month>`, and the outlined `Open Body` row.
- `life-inflight`: masthead with the range, numbered sections, hairline rows.
- `life-close`: masthead `CLOSE <MONTH> · 1 OF 9`, the proposed figure card, Skip and Next in the bar.
- Dark variants: no white boxes, no invisible text; the dusk field ink is near white.

Fix anything off before moving on, re-running this step.

- [ ] **Step 4: Run every gate**

```bash
cd LifeOSKit && swift test && cd .. && scripts/check-typography.sh
```

Expected: all tests pass; the typography guard prints nothing new beyond the violations it already reports on main (compare with `git stash`-free method: run it on `origin/main` in the main checkout and diff the output).

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Life/View/LifeDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(life): design-preview pages for the board, its screens and the shell"
```

---

### Task 11: Open the pull request

**Files:** none new.

- [ ] **Step 1: Rebase on the current main and push**

```bash
git fetch origin && git rebase origin/main
git push -u origin feat/editorial-shell-life
```

Expected: no conflicts (nothing else touches Life); the branch appears on origin.

- [ ] **Step 2: Open the PR** (no attribution footer, per the owner's rule)

```bash
gh pr create --base main --head feat/editorial-shell-life \
  --title "feat(shell): one header on every tab and Life on the editorial theme" \
  --body "$(cat <<'EOF'
## Summary

- One shell header on all five tabs: calendar assistant, LIFO as a word, Start, then the avatar, on a paper bar. Today no longer adds its own avatar; Notes drops its system title.
- Life on the editorial theme: masthead from a tested `BoardHeadline`, underline mode switch, a paper deck with 01 to 09 indices and chevrons, the open card as the one dusk field with ink bars, numbered sections on the detail, in-flight and close screens, and a teaching empty state. The sector tones are deleted.
- Design system: `RoundedBarChart` ink style, `EditorialEmptyState`, `ProfileAvatar` moved into the package, `ShellProfile` environment.
- Spec: docs/superpowers/specs/2026-10-05-editorial-shell-life-today-notes-coach-guide-design.md (PR 1 of 4).

## Verification

- LifeOSKit `swift test`: all suites pass, including the new `BoardHeadlineTests` and chart style tests.
- `scripts/check-typography.sh`: no new violations.
- Simulator design-preview pages `shell`, `life`, `life-empty`, `life-detail`, `life-inflight`, `life-close`, light and dark, reviewed against the spec.
EOF
)"
```

- [ ] **Step 3: Report**

Give the owner the PR link, the six screenshot paths, and the one-line merge command (`gh pr merge <n> --rebase --delete-branch`), since the permission classifier blocks merges from this side.
