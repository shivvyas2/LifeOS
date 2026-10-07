# Notes walkthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first time someone opens Notes after the welcome tour, the app walks them through five spotlight steps over the real screens (New, the File chip, the block picker, the To-dos chip, the library button), on a sample page it cleans up after; Settings can replay this walkthrough and the welcome tour.

**Architecture:** The walkthrough's parts that have nothing to do with Notes go in `DesignSystem`: the anchors, the five steps, the rule for which step comes next and where the card sits (all tested), an `@Observable` frame registry that views report into with `.walkthroughAnchor(_:)`, and the overlay that cuts a hole round an anchor. `Persistence` gains the tested rule for when the sample page is thrown away. The app owns the driver, `NotesWalkthrough`: it holds the step, makes and discards the sample page through `NotesViewModel`, asks `NotesHubScreen` to open the page or go back to the shelf, and skips a step whose anchor has not shown up within two seconds. `RootView` owns the driver, puts its frames in the environment, and draws the overlay above the tabs. Settings gains two replay rows routed through `ProfileScreen` to `RootView`.

**Tech Stack:** SwiftUI (`onGeometryChange`, `compositingGroup` + `blendMode(.destinationOut)`, `AccessibilityFocusState`), Observation, SwiftData, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the captures.

**Spec:** `docs/superpowers/specs/2026-10-06-notes-inbox-editor-walkthrough-design.md`, section 3, with the `notes-walkthrough --step=N` page and `WalkthroughScriptTests` from section 4. PR 3 of the three in section 5.

## Global Constraints

- Paper, ink, hairlines, quiet ink; the accent only for today and anything live; every button `.editorial(role)` or `.plain` around editorial content; fonts only from `LifeOSType`, `Editorial` or `lifeOSText(_:)`; no per-module palette. `scripts/check-typography.sh` reports nothing new versus the baseline in Task 0 (compare with line numbers stripped).
- `DesignSystem` has no dependencies; `Persistence` does not know the app's types. The `LifeOSKit` package also builds for macOS 26 (`platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")]`): nothing iOS-only in the new `DesignSystem` files (no `UIKit`, no `.topBarLeading`).
- Step sentences, verbatim and in this order:
  1. `notesNew`: "One tap starts a page. It lands in your Inbox until you file it."
  2. `notesFileChip`: "This says where the page lives. Tap it to move it anywhere."
  3. `notesBlockPicker`: "To-dos, headings and lists from here, or type / in the text."
  4. `notesTodos`: "Every open to-do from every page, in one list."
  5. `notesLibrary`: "Folders, favourites and habits live here."
- The sample page is titled exactly `Your first page`, made with `bucket: .areas`, unfiled (so it sits in the Inbox).
- The per-account flag is `hasSeenNotesWalkthrough` in `UserDefaults.currentAccount`. The welcome tour's flag is `hasSeenFirstRunTour` in the same suite, read by `AppShell`.
- Settings rows, under `At a glance` after `Widgets & Watch`: `Walk me through Notes again` and `Show the tour again`.
- The overlay: a 55% scrim, the anchor's frame cut out as a rounded rectangle with an 8pt outset, a card under the cut-out (above it when the cut-out's middle is in the lower half), `Next` (`Done` on the last step) as `.editorial(.primary, size: .compact)`, `Skip` as `.editorial(.quiet, size: .compact)`. Taps outside the card do nothing. VoiceOver lands on the sentence.
- A step whose anchor is not on screen within two seconds is skipped; no cut-out is ever drawn where nothing is.
- Nothing here changes what Notes syncs, the block model, `NoteIndexer` or the migrations. Deleting the sample page uses the existing tombstone `NotesStore.delete(_:)`.
- `LIfeOS/` is a synchronized folder: new files under it need no `project.pbxproj` edit.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution in commits or the PR body.
- Work happens in `/Users/shivvyas/LIfeOS/.claude/worktrees/notes-walkthrough` on `feat/notes-walkthrough`, cut from `feat/notes-editor` at 45cced2 (PR #29) so the plan reads the finished editor. After #29 merges it is rebased with `git rebase --onto origin/main 45cced2`. `Config/Secrets.xcconfig` is copied in and ignored.
- The simulator is `CalendarAsk iPhone 17`, id `B192EA65-BAA2-4814-A298-94A2F0C8FC87` (iOS 26.2). Peer sessions use the plain `iPhone 17`; do not install on it. Bundle id `com.shivvyas.lifeos`. The plain `sleep` is blocked; wait with `perl -e 'select(undef,undef,undef,4)'`. Tap automation has never landed on this machine; the tap checks are tried once and the PR says so if they do not land.
- `$OUT` is this session's scratchpad directory; the executor sets it in Task 0. DerivedData for this worktree goes to `~/Library/Developer/Xcode/DerivedData/notes-walkthrough`.

## Review Focus

1. A person who writes in the sample page during steps 2 and 3 must keep what they wrote; only an untouched sample is thrown away: `NotesStoreTests.theSampleStaysOnceItHoldsWords` (and its renamed and filed siblings) in Task 2.
2. A walkthrough replayed while Notes shows a folder or a search must still reach the To-dos chip, which only exists on the Inbox, All and To-dos selections: `start(notes:)` asks for the shelf and the hub answers `.showShelf` by selecting the Inbox and clearing the query (Task 4, Step 2). The app target has no tests, so the reviewer reads this path and the device run in Task 7 replays from a folder.
3. An anchor that never appears (the phone's library button sits in a navigation toolbar, the To-dos chip collapses into a menu at accessibility sizes) must skip its step rather than strand the person under a scrim with no card: `WalkthroughScriptTests.aMissingAnchorIsSkipped` and `nothingIsLeftWhenTheRestAreMissing` in Task 1, and the driver's two-second watch in Task 3.
4. The overlay's card must not cover the thing it points at: the card goes below a cut-out in the top half and above one in the lower half, `WalkthroughScriptTests.theCardSitsAwayFromTheCutOut` in Task 1, and the ten `--step=N` captures in Task 6.
5. A frame left behind by a view that has gone (the editor's chip after the pop back to the shelf) must not keep a step "available": `WalkthroughFramesTests.aViewThatGoesTakesItsFrame` in Task 1.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/Walkthrough.swift` (new) | `WalkthroughAnchor`, `WalkthroughStep`, `WalkthroughScript` (the steps, `next`, `isLast`, `cardSitsBelow`) |
| `LifeOSKit/Sources/DesignSystem/WalkthroughFrames.swift` (new) | The frame registry, its environment entry, `.walkthroughAnchor(_:)` |
| `LifeOSKit/Sources/DesignSystem/WalkthroughOverlay.swift` (new) | The scrim, the cut-out and the card |
| `LifeOSKit/Sources/DesignSystem/Tokens.swift` | `LifeOSTokens.scrim` |
| `LifeOSKit/Sources/DesignSystem/UnderlinePicker.swift` | Optional per-option anchors |
| `LifeOSKit/Tests/DesignSystemTests/WalkthroughScriptTests.swift`, `WalkthroughFramesTests.swift` (new) | Their tests |
| `LifeOSKit/Sources/Persistence/NoteBlock.swift`, `NotesStore.swift` | `NoteBlock.holdsNothing`, `NotesStore.deleteIfUntouched(_:title:)` |
| `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift` | The sample page's tests |
| `LIfeOS/Features/Notes/ViewModel/NotesWalkthrough.swift` (new) | The driver |
| `LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift` | `createWalkthroughSample()`, `discardWalkthroughSample(_:)` |
| `LIfeOS/Features/Notes/View/NoteShelfScreen.swift`, `NotesHubScreen.swift`, `NoteEditorScreen.swift`, `NoteAccessoryBar.swift` | The five anchors; the hub answers the driver and starts it on first visit |
| `LIfeOS/Features/Notes/View/NotesWalkthroughLayer.swift` (new) | Reads the driver and draws `WalkthroughOverlay` |
| `LIfeOS/App/RootView.swift`, `LIfeOS/App/AppShell.swift` | Owns the driver, draws the layer, wires the replays |
| `LIfeOS/Features/Settings/View/SettingsScreen.swift`, `ProfileScreen.swift` | The two rows and their callbacks |
| `LIfeOS/Features/Notes/View/NotesDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Page `notes-walkthrough --step=N` |

---

### Task 0: Worktree and baselines

- [ ] **Step 1: Confirm the worktree**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/notes-walkthrough
git status --short; git log --oneline -1   # expect 45cced2 or the plan commit on top of it
ls Config/Secrets.xcconfig || cp /Users/shivvyas/LIfeOS/Config/Secrets.xcconfig Config/Secrets.xcconfig
git check-ignore -q Config/Secrets.xcconfig && echo "secrets ignored"
gh pr view 29 --json state --jq .state   # if MERGED: git fetch origin && git rebase --onto origin/main 45cced2
```

- [ ] **Step 2: Baselines**

```bash
OUT=<this session's scratchpad>; echo "OUT=$OUT"
(cd LifeOSKit && swift test 2>&1 | grep -E "Test run with" | tail -1)
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort > $OUT/typo-walk-base.txt; wc -l < $OUT/typo-walk-base.txt
xcrun simctl list devices | grep "CalendarAsk iPhone 17"
df -h / | tail -1
```

Expected: 1468 tests in 209 suites pass (PR #29's count), a baseline file, the simulator listed, more than 5 GB free.

- [ ] **Step 3: Commit the plan**

```bash
git add docs/superpowers/plans/2026-10-07-notes-walkthrough.md
git commit -m "docs(plans): the Notes walkthrough" || echo "already committed"
```

---

### Task 1: The walkthrough's parts in DesignSystem

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/Walkthrough.swift`, `WalkthroughFrames.swift`, `WalkthroughOverlay.swift`
- Modify: `LifeOSKit/Sources/DesignSystem/Tokens.swift` (after `cardShadow`, line ~161), `UnderlinePicker.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/WalkthroughScriptTests.swift`, `WalkthroughFramesTests.swift`

**Interfaces:**
- Produces: `WalkthroughAnchor` (`notesNew`, `notesFileChip`, `notesBlockPicker`, `notesTodos`, `notesLibrary`); `WalkthroughStep(anchor:sentence:)`; `WalkthroughScript.notes: [WalkthroughStep]`, `WalkthroughScript.next(after: Int?, available: Set<WalkthroughAnchor>) -> Int?`, `WalkthroughScript.isLast(_ index: Int, available:) -> Bool`, `WalkthroughScript.cardSitsBelow(_ cutout: CGRect, in height: CGFloat) -> Bool`; `@MainActor @Observable final class WalkthroughFrames` with `frames: [WalkthroughAnchor: CGRect]`, `available: Set<WalkthroughAnchor>`, `report(_:_:)`; `EnvironmentValues.walkthroughFrames: WalkthroughFrames?`; `View.walkthroughAnchor(_ anchor: WalkthroughAnchor?)`; `WalkthroughOverlay(step:frame:isLast:onNext:onSkip:)`; `LifeOSTokens.scrim`; `UnderlinePicker(selection:options:anchors:)`.

- [ ] **Step 1: Write the failing tests**

`LifeOSKit/Tests/DesignSystemTests/WalkthroughScriptTests.swift`:

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct WalkthroughScriptTests {
    private let all = Set(WalkthroughAnchor.allCases)

    @Test func fiveStepsInOrder() {
        #expect(WalkthroughScript.notes.map(\.anchor) == [.notesNew, .notesFileChip, .notesBlockPicker, .notesTodos, .notesLibrary])
        #expect(WalkthroughScript.notes[0].sentence == "One tap starts a page. It lands in your Inbox until you file it.")
        #expect(WalkthroughScript.notes[4].sentence == "Folders, favourites and habits live here.")
    }

    @Test func itStartsAtTheFirstAndWalksOn() {
        #expect(WalkthroughScript.next(after: nil, available: all) == 0)
        #expect(WalkthroughScript.next(after: 0, available: all) == 1)
        #expect(WalkthroughScript.next(after: 3, available: all) == 4)
    }

    @Test func aMissingAnchorIsSkipped() {
        let noChip = all.subtracting([.notesFileChip])
        #expect(WalkthroughScript.next(after: 0, available: noChip) == 2)
    }

    @Test func nothingIsLeftWhenTheRestAreMissing() {
        #expect(WalkthroughScript.next(after: 4, available: all) == nil)
        #expect(WalkthroughScript.next(after: 2, available: [.notesNew]) == nil)
    }

    @Test func theLastAvailableStepIsLast() {
        #expect(WalkthroughScript.isLast(4, available: all))
        #expect(!WalkthroughScript.isLast(3, available: all))
        #expect(WalkthroughScript.isLast(3, available: all.subtracting([.notesLibrary])))
    }

    @Test func theCardSitsAwayFromTheCutOut() {
        #expect(WalkthroughScript.cardSitsBelow(CGRect(x: 300, y: 60, width: 60, height: 32), in: 800))
        #expect(!WalkthroughScript.cardSitsBelow(CGRect(x: 0, y: 700, width: 390, height: 44), in: 800))
    }
}
```

`LifeOSKit/Tests/DesignSystemTests/WalkthroughFramesTests.swift`:

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite @MainActor struct WalkthroughFramesTests {
    @Test func aReportedFrameIsAvailable() {
        let frames = WalkthroughFrames()
        frames.report(.notesNew, CGRect(x: 10, y: 10, width: 60, height: 30))
        #expect(frames.available == [.notesNew])
    }

    @Test func aViewThatGoesTakesItsFrame() {
        let frames = WalkthroughFrames()
        frames.report(.notesFileChip, CGRect(x: 10, y: 10, width: 60, height: 30))
        frames.report(.notesFileChip, nil)
        #expect(frames.available.isEmpty)
    }

    @Test func anEmptyFrameIsNotAPlace() {
        let frames = WalkthroughFrames()
        frames.report(.notesTodos, .zero)
        #expect(frames.frames[.notesTodos] == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter "Walkthrough" 2>&1 | tail -5`
Expected: build errors, `cannot find 'WalkthroughScript' in scope`.

- [ ] **Step 3: Write `Walkthrough.swift`**

```swift
import Foundation

/// A view the walkthrough can point at. Each one reports its own frame, so a
/// layout change moves the spotlight with it instead of leaving it on a
/// remembered rectangle.
public enum WalkthroughAnchor: String, CaseIterable, Hashable, Sendable {
    case notesNew, notesFileChip, notesBlockPicker, notesTodos, notesLibrary
}

public struct WalkthroughStep: Equatable, Sendable {
    public let anchor: WalkthroughAnchor
    public let sentence: String

    public init(anchor: WalkthroughAnchor, sentence: String) {
        self.anchor = anchor
        self.sentence = sentence
    }
}

/// The order of the steps and which one comes next.
public enum WalkthroughScript {
    public static let notes: [WalkthroughStep] = [
        WalkthroughStep(anchor: .notesNew, sentence: "One tap starts a page. It lands in your Inbox until you file it."),
        WalkthroughStep(anchor: .notesFileChip, sentence: "This says where the page lives. Tap it to move it anywhere."),
        WalkthroughStep(anchor: .notesBlockPicker, sentence: "To-dos, headings and lists from here, or type / in the text."),
        WalkthroughStep(anchor: .notesTodos, sentence: "Every open to-do from every page, in one list."),
        WalkthroughStep(anchor: .notesLibrary, sentence: "Folders, favourites and habits live here."),
    ]

    /// The next step after `index` (nil: before the first) whose anchor can
    /// be shown; nil when none remain.
    public static func next(after index: Int?, available: Set<WalkthroughAnchor>) -> Int? {
        let start = (index ?? -1) + 1
        guard start < notes.count else { return nil }
        return notes[start...].firstIndex { available.contains($0.anchor) }
    }

    public static func isLast(_ index: Int, available: Set<WalkthroughAnchor>) -> Bool {
        next(after: index, available: available) == nil
    }

    /// The card goes on the far side of the screen's middle from the cut-out,
    /// so it never covers what it is pointing at.
    public static func cardSitsBelow(_ cutout: CGRect, in height: CGFloat) -> Bool {
        cutout.midY < height / 2
    }
}
```

- [ ] **Step 4: Write `WalkthroughFrames.swift`**

```swift
import SwiftUI
import Observation

/// Where each anchor is on screen right now, in the global coordinate space.
/// A view that is not on screen has no frame.
@MainActor @Observable
public final class WalkthroughFrames {
    public private(set) var frames: [WalkthroughAnchor: CGRect] = [:]

    public init() {}

    public var available: Set<WalkthroughAnchor> { Set(frames.keys) }

    public func report(_ anchor: WalkthroughAnchor, _ frame: CGRect?) {
        if let frame, !frame.isEmpty { frames[anchor] = frame } else { frames[anchor] = nil }
    }
}

public extension EnvironmentValues {
    /// Nil outside a walkthrough's host, which makes every anchor a no-op.
    @Entry var walkthroughFrames: WalkthroughFrames? = nil
}

private struct WalkthroughAnchorModifier: ViewModifier {
    let anchor: WalkthroughAnchor?
    @Environment(\.walkthroughFrames) private var frames

    func body(content: Content) -> some View {
        if let anchor, let frames {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.report(anchor, $0) }
                .onDisappear { frames.report(anchor, nil) }
        } else {
            content
        }
    }
}

public extension View {
    /// Reports this view's frame for the walkthrough step that points at it.
    func walkthroughAnchor(_ anchor: WalkthroughAnchor?) -> some View {
        modifier(WalkthroughAnchorModifier(anchor: anchor))
    }
}
```

- [ ] **Step 5: Add the scrim token**

In `Tokens.swift`, after `cardShadow`:

```swift
    /// The walkthrough's dimming. Black in both appearances: ink is light in
    /// dark mode and would wash the screen out instead of dimming it.
    public static let scrim = Color.black.opacity(0.55)
```

- [ ] **Step 6: Write `WalkthroughOverlay.swift`**

```swift
import SwiftUI

/// The screen dimmed with one view cut out of the dimming, and a card saying
/// what that view is for. Modal: taps outside the card do nothing.
///
/// Expects to be laid out over the whole window with the safe area ignored;
/// `frame` is global and is moved into this view's space here.
public struct WalkthroughOverlay: View {
    let step: WalkthroughStep
    let frame: CGRect
    let isLast: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var scheme
    @AccessibilityFocusState private var sentenceFocused: Bool

    public init(step: WalkthroughStep, frame: CGRect, isLast: Bool,
                onNext: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.step = step
        self.frame = frame
        self.isLast = isLast
        self.onNext = onNext
        self.onSkip = onSkip
    }

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }

    public var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let cutout = frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
            let below = WalkthroughScript.cardSitsBelow(cutout, in: proxy.size.height)

            ZStack {
                ZStack {
                    Rectangle().fill(LifeOSTokens.scrim)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .contentShape(.rect)
                .onTapGesture {}
                .accessibilityHidden(true)

                card
                    .frame(maxWidth: 360)
                    .padding(.horizontal, Space.x2)
                    .padding(.top, below ? cutout.maxY + Space.x1 : 0)
                    .padding(.bottom, below ? 0 : proxy.size.height - cutout.minY + Space.x1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: frame)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(step.sentence)
                .lifeOSText(.body)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($sentenceFocused)
            HStack {
                Button("Skip", action: onSkip)
                    .buttonStyle(.editorial(.quiet, size: .compact))
                Spacer()
                Button(isLast ? "Done" : "Next", action: onNext)
                    .buttonStyle(.editorial(.primary, size: .compact))
            }
        }
        .padding(Space.x3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LifeOSTokens.cardSurface.resolve(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ink.opacity(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .onAppear { sentenceFocused = true }
        .onChange(of: step) { sentenceFocused = true }
    }
}
```

The spec names `LifeOSType.body`; `lifeOSText(.body)` is the same step scaled with Dynamic Type, which the spec also asks for. Say so in the PR body.

- [ ] **Step 7: Per-option anchors on `UnderlinePicker`**

Replace its stored properties and `init` with:

```swift
    @Binding var selection: Value
    let options: [(Value, String)]
    /// The walkthrough points at single tabs, so each option can carry an anchor.
    let anchors: [Value: WalkthroughAnchor]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    public init(selection: Binding<Value>, options: [(Value, String)], anchors: [Value: WalkthroughAnchor] = [:]) {
        _selection = selection
        self.options = options
        self.anchors = anchors
    }
```

In `body`'s accessibility branch, add after `.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)`:

```swift
            // One menu stands for every tab at accessibility sizes, so it
            // carries the anchor of whichever tab has one.
            .walkthroughAnchor(anchors.values.first)
```

In `tabs`, after `.accessibilityAddTraits(selection == value ? .isSelected : [])`:

```swift
                .walkthroughAnchor(anchors[value])
```

- [ ] **Step 8: Run the tests and both builds**

```bash
cd LifeOSKit && swift test --filter "Walkthrough" 2>&1 | grep -E "Test run with|error" | tail -3
swift build 2>&1 | tail -2                              # macOS build of the package
```

Expected: 9 tests pass; the package builds for macOS.

- [ ] **Step 9: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem LifeOSKit/Tests/DesignSystemTests
git commit -m "feat(design): a walkthrough script, anchors that report their frames, and an overlay that cuts round one"
```

---

### Task 2: When the sample page goes

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteBlock.swift` (after `isEmpty`, line ~215), `LifeOSKit/Sources/Persistence/NotesStore.swift` (after `delete(_ document:)`, line ~494)
- Test: `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift`

**Interfaces:**
- Produces: `NoteBlock.holdsNothing: Bool`; `NotesStore.deleteIfUntouched(_ document: NoteDocument, title: String) throws -> Bool` (true when it deleted).

- [ ] **Step 1: Write the failing tests** (append inside `NotesStoreTests`)

```swift
    @Test func anUntouchedSampleGoes() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Your first page", bucket: .areas)
        #expect(try store.deleteIfUntouched(page, title: "Your first page"))
        #expect(page.deletedAt != nil)
    }

    @Test func aBlankToDoIsStillUntouched() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Your first page", bucket: .areas,
                                            blocks: [NoteBlock(kind: .todo, text: "  ")])
        #expect(try store.deleteIfUntouched(page, title: "Your first page"))
    }

    @Test func theSampleStaysOnceItHoldsWords() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Your first page", bucket: .areas,
                                            blocks: [NoteBlock(text: "Buy milk")])
        #expect(try !store.deleteIfUntouched(page, title: "Your first page"))
        #expect(page.deletedAt == nil)
    }

    @Test func theSampleStaysOnceRenamed() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Groceries", bucket: .areas)
        #expect(try !store.deleteIfUntouched(page, title: "Your first page"))
    }

    @Test func theSampleStaysOnceFiled() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Your first page", bucket: .areas)
        try store.move(page, to: .projects, folderID: nil)
        #expect(try !store.deleteIfUntouched(page, title: "Your first page"))
    }

    @Test func aDividerOrADrawingIsSomething() throws {
        let store = try makeStore()
        let ruled = try store.createDocument(title: "Your first page", bucket: .areas,
                                             blocks: [NoteBlock(kind: .divider)])
        #expect(try !store.deleteIfUntouched(ruled, title: "Your first page"))
        let drawn = try store.createDocument(title: "Your first page", bucket: .areas,
                                             blocks: [NoteBlock(kind: .sketch, drawing: Data([1, 2, 3]))])
        #expect(try !store.deleteIfUntouched(drawn, title: "Your first page"))
    }
```

Check first that `NoteBlockKind` has `.todo` (`grep -n "case todo" LifeOSKit/Sources/Persistence/NoteBlock.swift`); use the real case name if it differs. Check that `move` sets `filedAt` (`grep -n "filedAt" LifeOSKit/Sources/Persistence/NotesStore.swift`); PR 1 made it so.

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter NotesStoreTests 2>&1 | tail -5`
Expected: `value of type 'NotesStore' has no member 'deleteIfUntouched'`.

- [ ] **Step 3: Implement**

In `NoteBlock.swift`, after `isEmpty`:

```swift
    /// Nothing anyone made: no words, no drawing, and not a rule, which is
    /// something put there on purpose even though it holds no text.
    public var holdsNothing: Bool {
        switch kind {
        case .sketch: isBlankSketch
        case .divider: false
        default: isEmpty
        }
    }
```

In `NotesStore.swift`, after `delete(_ document:)`:

```swift
    /// Deletes a page the app made for someone only if they left it as it was
    /// made: still titled `title`, still in the Inbox, nothing in its blocks.
    /// Anything they wrote, renamed or filed is theirs and stays.
    @discardableResult
    public func deleteIfUntouched(_ document: NoteDocument, title: String) throws -> Bool {
        guard document.title == title, document.isInInbox,
              document.blocks.allSatisfy(\.holdsNothing) else { return false }
        try delete(document)
        return true
    }
```

- [ ] **Step 4: Run the whole suite**

Run: `cd LifeOSKit && swift test 2>&1 | grep -E "Test run with" | tail -1`
Expected: 1468 + 9 + 6 = 1483 tests pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift
git commit -m "feat(persistence): a page the app made goes only if it was left as made"
```

---

### Task 3: The driver

**Files:**
- Create: `LIfeOS/Features/Notes/ViewModel/NotesWalkthrough.swift`
- Modify: `LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift` (after `openTodaysJournal()`, line ~276)

**Interfaces:**
- Consumes: `WalkthroughScript`, `WalkthroughFrames`, `WalkthroughAnchor`, `NotesStore.deleteIfUntouched(_:title:)`.
- Produces: `@MainActor @Observable final class NotesWalkthrough` with `frames: WalkthroughFrames`, `stepIndex: Int?` (read-only outside), `currentStep: WalkthroughStep?`, `isLastStep: Bool`, `request: NotesWalkthrough.Request?`, `func start(notes: NotesViewModel)`, `func next()`, `func skip()`, `func consumeRequest()`, `static let sampleTitle = "Your first page"`, `static let seenKey = "hasSeenNotesWalkthrough"`; `enum Request: Equatable { case showShelf, openPage(UUID) }`. `NotesViewModel.createWalkthroughSample() -> UUID?`, `NotesViewModel.discardWalkthroughSample(_ id: UUID)`. `EnvironmentValues.notesWalkthrough: NotesWalkthrough?`.

The app target has no test target (spec section 4); the driver is checked through Task 6's pages and the review.

- [ ] **Step 1: The sample page on `NotesViewModel`**

```swift
    /// The walkthrough's page: unfiled, so it sits in the Inbox the first
    /// step talks about.
    func createWalkthroughSample() -> UUID? {
        guard let store else { return nil }
        do {
            let document = try store.createDocument(title: NotesWalkthrough.sampleTitle, bucket: .areas)
            load()
            requestSync()
            return document.id
        } catch {
            assertionFailure("Walkthrough page create failed: \(error)")
            return nil
        }
    }

    /// Throws the walkthrough's page away unless the person made it theirs.
    func discardWalkthroughSample(_ id: UUID) {
        mutate(id) { store, document in
            try store.deleteIfUntouched(document, title: NotesWalkthrough.sampleTitle)
        }
    }
```

Read `mutate(_:_:)` first (`grep -n "private func mutate(" -A15 LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift`): it must fetch the document, run the closure, then `load()` and `requestSync()`. If its closure type is `(NotesStore, NoteDocument) throws -> Void`, wrap the call as `_ = try store.deleteIfUntouched(...)`.

- [ ] **Step 2: Write `NotesWalkthrough.swift`**

```swift
import SwiftUI
import Observation
import DesignSystem
import Persistence

/// Walks someone through Notes over the real screens.
///
/// The app drives; the person only taps Next or Skip. Steps 1, 4 and 5 point
/// at the shelf, 2 and 3 at a sample page the walkthrough opens, so moving
/// between them is a request the hub carries out (`request`), because only the
/// hub knows whether a page is pushed or shown beside the shelf.
@MainActor @Observable
final class NotesWalkthrough {
    enum Request: Equatable {
        case showShelf
        case openPage(UUID)
    }

    static let sampleTitle = "Your first page"
    static let seenKey = "hasSeenNotesWalkthrough"
    /// How long a step waits for its anchor before it is skipped.
    static let anchorWait: Duration = .seconds(2)

    let frames = WalkthroughFrames()
    private(set) var stepIndex: Int?
    private(set) var request: Request?
    private weak var notes: NotesViewModel?
    private var samplePageID: UUID?
    /// Anchors that did not turn up in time this run; `next` passes over them.
    private var missing: Set<WalkthroughAnchor> = []
    private var watch: Task<Void, Never>?

    var currentStep: WalkthroughStep? { stepIndex.map { WalkthroughScript.notes[$0] } }

    var isLastStep: Bool {
        guard let stepIndex else { return false }
        return WalkthroughScript.isLast(stepIndex, available: candidates)
    }

    private var candidates: Set<WalkthroughAnchor> { Set(WalkthroughAnchor.allCases).subtracting(missing) }

    private static func isEditorStep(_ index: Int) -> Bool {
        [.notesFileChip, .notesBlockPicker].contains(WalkthroughScript.notes[index].anchor)
    }

    func start(notes: NotesViewModel) {
        guard stepIndex == nil else { return }
        self.notes = notes
        missing = []
        request = .showShelf
        move(to: WalkthroughScript.next(after: nil, available: candidates))
    }

    func next() { move(to: WalkthroughScript.next(after: stepIndex, available: candidates)) }

    func skip() { finish() }

    func consumeRequest() { request = nil }

    /// Enters a step: the sample page for the editor steps, the shelf again
    /// when coming back from them. No step left means the walkthrough is over.
    private func move(to index: Int?) {
        guard let index else { return finish() }
        if Self.isEditorStep(index) {
            if samplePageID == nil, let id = notes?.createWalkthroughSample() {
                samplePageID = id
                request = .openPage(id)
            }
        } else if let stepIndex, Self.isEditorStep(stepIndex) {
            request = .showShelf
        }
        stepIndex = index
        watchForAnchor(of: index)
    }

    /// Skips a step whose anchor has not appeared in time, so the screen is
    /// never left dimmed with nothing cut out and no card.
    private func watchForAnchor(of index: Int) {
        watch?.cancel()
        watch = Task { [weak self] in
            try? await Task.sleep(for: Self.anchorWait)
            guard let self, !Task.isCancelled, self.stepIndex == index else { return }
            let anchor = WalkthroughScript.notes[index].anchor
            guard self.frames.frames[anchor] == nil else { return }
            self.missing.insert(anchor)
            self.next()
        }
    }

    private func finish() {
        watch?.cancel()
        if let samplePageID {
            notes?.discardWalkthroughSample(samplePageID)
            request = .showShelf
        }
        samplePageID = nil
        stepIndex = nil
        UserDefaults.currentAccount.set(true, forKey: Self.seenKey)
    }
}

extension EnvironmentValues {
    /// Owned by `RootView`; nil in previews that do not run a walkthrough.
    @Entry var notesWalkthrough: NotesWalkthrough? = nil
}
```

Two behaviours to keep when tidying: a step that times out calls `next()`, so the editor-to-shelf request still fires when the block picker never shows; and `finish()` asks for the shelf only when a sample page was opened, so skipping at step 1 leaves the shelf where it is.

- [ ] **Step 3: Build**

```bash
xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/notes-walkthrough build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Notes/ViewModel
git commit -m "feat(notes): a walkthrough driver that opens a sample page and skips a step it cannot show"
```

---

### Task 4: Anchors, the hub's part and the overlay in the shell

**Files:**
- Create: `LIfeOS/Features/Notes/View/NotesWalkthroughLayer.swift`
- Modify: `NoteShelfScreen.swift` (`mastheadRow` ~line 66, `chips` ~line 90), `NotesHubScreen.swift` (`compactShell` toolbar ~line 270, `body`), `NoteEditorScreen.swift` (`metadata` ~line 219), `NoteAccessoryBar.swift` (`formattingBar`), `LIfeOS/App/RootView.swift`

**Interfaces:**
- Consumes: `NotesWalkthrough.start(notes:)`, `next()`, `skip()`, `request`, `consumeRequest()`, `currentStep`, `isLastStep`, `frames`; `.walkthroughAnchor(_:)`; `UnderlinePicker(…anchors:)`; `WalkthroughOverlay`.
- Produces: `NotesWalkthroughLayer(walkthrough:)`.

- [ ] **Step 1: The five anchors**

- `NoteShelfScreen.mastheadRow`: `.walkthroughAnchor(.notesNew)` on the `New` button (after `.accessibilityHint`), and `.walkthroughAnchor(.notesLibrary)` on the `sidebar.leading` button (the iPad's).
- `NoteShelfScreen.chips`: pass `anchors: [.todos: .notesTodos]` to `UnderlinePicker`.
- `NotesHubScreen.compactShell`: `.walkthroughAnchor(.notesLibrary)` on the `sidebar.left` toolbar button's `Image` label (the phone's). A toolbar may host the label outside the reporting view's hierarchy; if the `--step=5` capture in Task 6 shows no cut-out, the step is skipped by the two-second watch, which is the specified behaviour, and the PR says so.
- `NoteEditorScreen.metadata`: `.walkthroughAnchor(.notesFileChip)` on the File chip button (after `.accessibilityHint("Choose where this page lives")`). The chip sits inside a `ViewThatFits`; only the chosen candidate appears, so only it reports.
- `NoteAccessoryBar.formattingBar`: `.walkthroughAnchor(.notesBlockPicker)` on the `NoteBlockPicker` view inside it (read the property first: `grep -n "formattingBar" -A20 LIfeOS/Features/Notes/View/NoteAccessoryBar.swift`).

- [ ] **Step 2: The hub answers the driver and starts it on first visit**

In `NotesHubScreen`, add:

```swift
    @Environment(\.notesWalkthrough) private var walkthrough
    @AppStorage(NotesWalkthrough.seenKey, store: .currentAccount) private var hasSeenNotesWalkthrough = false
    @AppStorage("hasSeenFirstRunTour", store: .currentAccount) private var hasSeenFirstRunTour = false
```

and on `body`, after `.focusedSceneValue(\.notesCommands, commandTarget)`:

```swift
        // Once per account, and never over the welcome tour.
        .onAppear {
            guard let walkthrough, !hasSeenNotesWalkthrough, hasSeenFirstRunTour else { return }
            walkthrough.start(notes: model)
        }
        .onChange(of: walkthrough?.request) { _, request in
            guard let request else { return }
            switch request {
            case .showShelf:
                // The To-dos chip only exists on the Inbox, All and To-dos
                // selections, and a search hides it too.
                model.selection = .inbox
                model.query = ""
                path.removeAll()
                openPage = nil
            case .openPage(let id):
                open(id, focus: .firstBlock)
            }
            walkthrough?.consumeRequest()
        }
```

Check `model.query` is settable (`grep -n "var query" LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift`).

- [ ] **Step 3: `NotesWalkthroughLayer.swift`**

```swift
import SwiftUI
import DesignSystem

/// The walkthrough's overlay, drawn only once the current step's anchor is on
/// screen: while a page is opening there is no cut-out to draw yet.
struct NotesWalkthroughLayer: View {
    let walkthrough: NotesWalkthrough

    var body: some View {
        if let step = walkthrough.currentStep, let frame = walkthrough.frames.frames[step.anchor] {
            WalkthroughOverlay(step: step, frame: frame, isLast: walkthrough.isLastStep,
                               onNext: { walkthrough.next() }, onSkip: { walkthrough.skip() })
                .ignoresSafeArea()
                .transition(.opacity)
        }
    }
}
```

- [ ] **Step 4: `RootView` owns it**

Add `@State private var notesWalkthrough = NotesWalkthrough()` beside `@State private var notes = NotesViewModel()` (line ~73). After the `Group { if sizeClass == .regular { wideShell } else { compactShell } }` that opens `body` (line ~145), before the first `.sheet`:

```swift
        // Above the tabs and the nav bar, below every sheet and cover.
        .overlay { NotesWalkthroughLayer(walkthrough: notesWalkthrough) }
```

With the other environment values (line ~231):

```swift
        .environment(\.walkthroughFrames, notesWalkthrough.frames)
        .environment(\.notesWalkthrough, notesWalkthrough)
```

- [ ] **Step 5: Build, typography, commit**

```bash
xcodebuild ... build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -5   # the Task 3 command
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort | comm -23 - $OUT/typo-walk-base.txt
git add LIfeOS
git commit -m "feat(notes): the walkthrough runs once per account over the shelf and a sample page"
```

Expected: `BUILD SUCCEEDED`, nothing new from the typography check.

---

### Task 5: The replay rows

**Files:**
- Modify: `LIfeOS/Features/Settings/View/SettingsScreen.swift` (stored properties ~line 12, `At a glance` ~line 65), `ProfileScreen.swift` (properties ~line 16, `settingsScreen` ~line 71), `LIfeOS/App/RootView.swift` (the `showSettings` cover ~line 174), `LIfeOS/App/AppShell.swift` (after `.task` that raises the tour, ~line 89)

**Interfaces:**
- Consumes: `NotesWalkthrough.start(notes:)`.
- Produces: `SettingsScreen.onReplayNotesWalkthrough: () -> Void`, `SettingsScreen.onReplayTour: () -> Void`, the same two on `ProfileScreen`.

- [ ] **Step 1: The rows**

In `SettingsScreen`, after `var onSignOut: () -> Void = {}`:

```swift
    var onReplayNotesWalkthrough: () -> Void = {}
    var onReplayTour: () -> Void = {}
```

In the `At a glance` `AccountPanel`, after the `Widgets & Watch` link:

```swift
                    Divider()
                    replayRow("Walk me through Notes again", systemImage: "hand.point.up.left", action: onReplayNotesWalkthrough)
                    Divider()
                    replayRow("Show the tour again", systemImage: "sparkles", action: onReplayTour)
```

and a helper beside `divider`:

```swift
    /// Reads like the links above it, but closes Settings rather than pushing.
    private func replayRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage).font(LifeOSType.rowTitle)
                Spacer()
                Image(systemName: "chevron.right").font(LifeOSType.caption.weight(.semibold))
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
```

Match the foreground of the two `NavigationLink` rows above (read how they are tinted first) so the four rows look alike.

- [ ] **Step 2: Through `ProfileScreen`**

Add the same two properties after its `onSignOut`, and pass them on in `settingsScreen`: `SettingsScreen(model: settings, …, onSignOut: onSignOut, onReplayNotesWalkthrough: onReplayNotesWalkthrough, onReplayTour: onReplayTour)` (keep the existing argument order; add the two at the end).

- [ ] **Step 3: `RootView` closes Settings, then acts**

Add:

```swift
    /// What a replay row asked for, done once the Settings cover has gone.
    @State private var afterSettings: (() -> Void)?
    @AppStorage("hasSeenFirstRunTour", store: .currentAccount) private var hasSeenFirstRunTour = false
```

Change the cover to:

```swift
        .fullScreenCover(isPresented: $showSettings, onDismiss: {
            afterSettings?()
            afterSettings = nil
            presentDeferredCoach()
        }) {
            ProfileScreen(
                settings: settings, whoop: whoop, fitbit: fitbit, health: health, plaid: plaid,
                stats: profileStats, highlights: profileHighlights,
                allTime: profileAllTime, socialActivity: socialActivity, onSignOut: onSignOut,
                onReplayNotesWalkthrough: {
                    afterSettings = {
                        tab = .notes
                        notesWalkthrough.start(notes: notes)
                    }
                    showSettings = false
                },
                onReplayTour: {
                    afterSettings = { hasSeenFirstRunTour = false }
                    showSettings = false
                }
            )
        }
```

- [ ] **Step 4: `AppShell` raises the tour again**

After the `.task` that shows the tour on first run:

```swift
                // Settings' "Show the tour again" clears the flag.
                .onChange(of: hasSeenFirstRunTour) { _, seen in
                    if !seen { withAnimation(.easeIn(duration: 0.25)) { showTour = true } }
                }
```

- [ ] **Step 5: Build, typography, commit**

```bash
xcodebuild ... build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -5
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort | comm -23 - $OUT/typo-walk-base.txt
git add LIfeOS
git commit -m "feat(settings): replay the Notes walkthrough and the welcome tour"
```

---

### Task 6: The preview page and captures

**Files:**
- Modify: `LIfeOS/Features/Notes/View/NotesDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift:101`

- [ ] **Step 1: Route the page**

In `HealthActivityDesignPreview`, add `"notes-walkthrough"` to the list on line 101 that sends pages to `NotesDesignPreview(page:)`.

- [ ] **Step 2: Draw a step over the fixture**

In `NotesDesignPreview`, add `@State private var frames = WalkthroughFrames()` and a case before `default:`:

```swift
            // `--step=N`, 1 to 5: the overlay over the shelf (1, 4, 5) or the
            // sample page with its picker up (2, 3).
            case "notes-walkthrough":
                walkthroughPage
```

```swift
    private var step: Int {
        let raw = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--step=") }?.dropFirst(7)
        return min(max(Int(raw ?? "1") ?? 1, 1), 5)
    }

    @ViewBuilder private var walkthroughPage: some View {
        let current = WalkthroughScript.notes[step - 1]
        Group {
            if step == 2 || step == 3 {
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, focusOnAppear: .firstBlock, onOpenLinked: { _ in })
                }
            } else {
                NotesHubScreen(model: fixture.notes, plan: fixture.plan, onAddHabit: {})
            }
        }
        .environment(\.walkthroughFrames, frames)
        .overlay {
            if let frame = frames.frames[current.anchor] {
                WalkthroughOverlay(step: current, frame: frame, isLast: step == 5, onNext: {}, onSkip: {})
                    .ignoresSafeArea()
            }
        }
    }
```

No `\.notesWalkthrough` here, so the hub does not start a real one over the page.

- [ ] **Step 3: Build, install, capture ten**

```bash
xcodebuild ... build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3
APP=$(find ~/Library/Developer/Xcode/DerivedData/notes-walkthrough -name "LIfeOS.app" -path "*iphonesimulator*" | head -1)
SIM=B192EA65-BAA2-4814-A298-94A2F0C8FC87
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl install $SIM "$APP"
for n in 1 2 3 4 5; do for mode in light dark; do
  xcrun simctl ui $SIM appearance $mode
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview --page=notes-walkthrough --step=$n
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot $OUT/walk-$n-$mode.png
done; done
```

Read each capture. Expected: a dimmed screen with one rounded hole round, in order, `New`; the File chip (`Inbox`); the picker row above the keyboard; the `To-dos` tab; the library button. The card sits below the hole for 1, 2, 4 and 5 and above it for 3, says the step's sentence, and reads `Done` on 5. If a capture has no overlay, that anchor is not reporting: fix it, or for the phone's toolbar button (step 5) record it in the PR as the skip described in Task 4.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS
git commit -m "feat(notes): a preview page for each walkthrough step"
```

---

### Task 7: Whole-branch verification and the PR

- [ ] **Step 1: Gates**

```bash
(cd LifeOSKit && swift test 2>&1 | grep -E "Test run with" | tail -1)     # 1483 or more
(cd LifeOSKit && swift build 2>&1 | tail -1)                               # macOS
scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort | comm -23 - $OUT/typo-walk-base.txt   # nothing
xcodebuild -project LIfeOS.xcodeproj -scheme AlmanacWidgetsExtension -destination 'id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/notes-walkthrough build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

`DesignSystem` changed, so the widget builds too (list schemes with `xcodebuild -list -project LIfeOS.xcodeproj` if the name differs).

- [ ] **Step 2: Try the real flow once**

Launch the app normally on the simulator, sign in as the dev account if one is set up, and try `Settings > Walk me through Notes again`, tapping `Next` five times. Tap automation has never landed here; if this does not, say so in the PR and ask for a device run: first visit to Notes after the tour, Next through all five, a replay started while a folder is selected, the sample page gone afterwards; again writing a word on the sample page, which must stay; `Show the tour again` brings the welcome tour back.

- [ ] **Step 3: Fresh whole-branch review**

Ask one fresh reviewer (most capable model) to review `git diff 45cced2..HEAD` (or `origin/main..HEAD` after the rebase) against spec section 3 and this plan's Review Focus. Fix Critical and Important findings in one `fix(notes): close the gaps the review found` commit; list the minors in the PR body.

- [ ] **Step 4: Push and open the PR**

Only once #29 is on `main` (rebase per Global Constraints first, then re-run Step 1).

```bash
git push -u origin feat/notes-walkthrough
gh pr create --base main --title "feat(notes): a five-step walkthrough over the real screens, replayable from Settings" --body-file $OUT/pr-walkthrough-body.md
```

The body follows #29's shape: Summary bullets, Spec and Plan paths, Verification (test count, typography, builds, the ten captures, what was not tapped), the review's outcome, Deferred minors. Mention the `lifeOSText(.body)` deviation and, if it happened, the phone's library step being skipped.
