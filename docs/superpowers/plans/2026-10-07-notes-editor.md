# Notes editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new page opens ready to write and Return in the title lands the caret in the body; the strip above the keyboard is a row of labelled chips that change a block's kind without losing its words; a checked to-do reads struck through and can be ticked with a swipe.

**Architecture:** Three small tested rules go into the package: `NoteBlockEditor.changeKind` (the kind changes, the words stay), `NoteBlockEditor.titleWithoutReturn` (the vertical title field puts Return into the text; the editor reads it as "go to the body"), and `NoteBlockKind.barOrder`/`moreOrder`/`chipTitle` (which six kinds sit on the bar and which six behind `More`, every kind once); `TodoSwipe.ticks` in `DesignSystem` decides when a drag is the tick gesture. In the app, `NoteBlockPicker` replaces the icon-only formatting bar inside `NoteAccessoryBar`, `NoteEditorViewModel` gains `pickBlockKind` and `submitTitle`, `BlockTextView` learns a `strikethrough` flag, `NoteBlockRow` strikes checked to-dos, draws their gutter mark in ink, and carries the swipe with a light haptic, and `NoteEditorScreen` wires the title's Return. Two preview pages draw the struck page and the picker.

**Tech Stack:** SwiftUI, SwiftData, UIKit (`UITextView` attributes), Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-06-notes-inbox-editor-walkthrough-design.md`, section 2 (the focus-on-appear itself shipped in PR 1; this PR adds the way into the body) and the `notes-editor-picker` page of section 4. PR 2 of the three in section 5.

## Global Constraints

- Paper, ink, hairlines, quiet ink; the accent only for today and anything live; every button `.editorial(role)` or `.plain` around editorial content; fonts only from `LifeOSType` and `Editorial`; no per-module palette. `scripts/check-typography.sh` reports nothing new versus the baseline in Task 0 (line numbers may move; compare with them stripped, as PR 1 did).
- `DesignSystem` has no dependencies and `Persistence` does not know the app's types. `TodoSwipe` takes two `CGFloat`s, not a gesture value.
- Nothing here changes what Notes syncs, the block model, `NoteIndexer` or the migrations. `NoteBlock` gains no field; a struck to-do is a checked to-do drawn differently.
- The `/` menu and the markdown prefixes are unchanged: `applySlashCommand` keeps calling `transform` with an empty string, because what was typed after the slash was a command. Only the bar's pick keeps the words.
- The `LifeOSKit` package also builds for macOS 26: nothing iOS-only in it.
- Spec section 2's meta row (the File chip, then the entry date or the status menu, then the save state) already reads that way after PR 1; no task touches it.
- `LIfeOS/` is a synchronized folder: new files under it need no `project.pbxproj` edit.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution in commits or the PR body.
- Work happens in `/Users/shivvyas/LIfeOS/.claude/worktrees/notes-editor` on `feat/notes-editor`, cut from `feat/notes-inbox` at 692089d so the plan reads the real code. It is rebased onto `main` after PR #27 (`feat/notes-inbox`) merges: `git rebase --onto origin/main 692089d`, which replays only this plan's commits. `Config/Secrets.xcconfig` is copied in and ignored.
- The simulator for builds and captures is `CalendarAsk iPhone 17`, id `B192EA65-BAA2-4814-A298-94A2F0C8FC87` (iOS 26.2). Peer sessions use the plain `iPhone 17`; do not install on it. Bundle id `com.shivvyas.lifeos`. The plain `sleep` is blocked; wait with `perl -e 'select(undef,undef,undef,4)'`. Tap automation has not landed on this machine in two runs; the simulator checks are attempted once and the PR says so if they do not land.
- `$OUT` is this session's scratchpad directory; the executor sets it in Task 0.

## Review Focus

1. A kind picked from the bar must keep the block's words, or a sentence turned into a to-do vanishes: `NoteBlockEditorTests.changingTheKindKeepsTheWords` in Task 1.
2. Picking `Divider` or `Sketch` from the bar must leave the caret somewhere to type, or the person is stranded on a block that takes no text: `NoteBlockEditorTests.changingToARuleKeepsACaretBelow` in Task 1.
3. Return in the title must not leave a newline in it, since the vertical field inserts one before the editor hears about it: `NoteBlockEditorTests.aReturnTypedInTheTitleIsStrippedAndNoticed` in Task 1.
4. A drag that is mostly downward must scroll the page, never tick a to-do: `TodoSwipeTests.aScrollIsNotATick` in Task 2.
5. Every block kind must be reachable from the picker exactly once, or a kind the slash menu offers has no chip and no menu row: `NoteBlockTests.thePickerReachesEveryKindOnce` in Task 1.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/Persistence/NoteBlockEditor.swift` | `changeKind(_:at:to:)`, `titleWithoutReturn(_:)` |
| `LifeOSKit/Sources/Persistence/NoteBlock.swift` | `NoteBlockKind.barOrder`, `moreOrder`, `chipTitle` |
| `LifeOSKit/Tests/PersistenceTests/NoteBlockEditorTests.swift`, `NoteBlockTests.swift` | Their tests |
| `LifeOSKit/Sources/DesignSystem/TodoSwipe.swift` (new) | When a drag is the tick gesture |
| `LifeOSKit/Tests/DesignSystemTests/TodoSwipeTests.swift` (new) | Its test |
| `LIfeOS/Features/Notes/View/BlockTextView.swift` | `strikethrough` through `apply`, `restyle`, `attributed` |
| `LIfeOS/Features/Notes/View/NoteBlockRow.swift` | Struck text, ink gutter mark, the swipe and its haptic |
| `LIfeOS/Features/Notes/View/NoteBlockPicker.swift` (new) | The labelled chips, `More`, Indent, Outdent, Draw |
| `LIfeOS/Features/Notes/View/NoteAccessoryBar.swift` | The formatting bar becomes the picker; `onChangeKind` |
| `LIfeOS/Features/Notes/ViewModel/NoteEditorViewModel.swift` | `pickBlockKind(_:)`, `submitTitle()` |
| `LIfeOS/Features/Notes/View/NoteEditorScreen.swift` | The title's Return into the body; the bar's new callback |
| `LIfeOS/Features/Notes/View/NotesDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Pages `notes-editor`, `notes-editor-picker` |

---

### Task 0: Rebase, worktree and baselines

Do not start until `feat/notes-inbox` (PR #27) is on `main`.

- [ ] **Step 1: Rebase onto main and confirm PR 1's pieces are here**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/notes-editor
git fetch origin
git cat-file -e origin/main:LIfeOS/Features/Notes/View/NoteFilingSheet.swift && echo "notes inbox is on main" || echo "STOP: PR #27 not merged"
git rebase --onto origin/main 692089d && git log --oneline -3
grep -n "func pickBlockKind\|focusOnAppear" LIfeOS/Features/Notes/View/NoteEditorScreen.swift | head -2
ls Config/Secrets.xcconfig || cp /Users/shivvyas/LIfeOS/Config/Secrets.xcconfig Config/Secrets.xcconfig
git check-ignore -q Config/Secrets.xcconfig && echo "secrets ignored"
```

Expected: `notes inbox is on main`, a clean rebase with only this plan's commit on top of `origin/main`, `focusOnAppear` found, the secrets file ignored.

- [ ] **Step 2: Baselines**

```bash
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/068489d1-9b0b-4686-8c3b-702504137000/scratchpad; echo "OUT=$OUT"
(cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*Test run with" | tail -1)
scripts/check-typography.sh > $OUT/typo-editor-base.txt 2>&1; echo "typography baseline lines: $(wc -l < $OUT/typo-editor-base.txt)"
xcrun simctl list devices | grep "CalendarAsk" || xcrun simctl create "CalendarAsk iPhone 17" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
df -h / | tail -1
```

Expected: the suite passes (1458 tests in 208 suites on main after PR #27, or more), a baseline file, the simulator listed, more than 5 GB free.

- [ ] **Step 3: Commit the plan if it is not committed yet**

```bash
git add docs/superpowers/plans/2026-10-07-notes-editor.md
git commit -m "docs(plans): the Notes editor" || echo "already committed"
```

---

### Task 1: The rules in the package

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteBlockEditor.swift`, `LifeOSKit/Sources/Persistence/NoteBlock.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/NoteBlockEditorTests.swift`, `LifeOSKit/Tests/PersistenceTests/NoteBlockTests.swift`

**Interfaces:**
- Produces: `NoteBlockEditor.changeKind(_ blocks: [NoteBlock], at id: UUID, to kind: NoteBlockKind) -> Result`; `NoteBlockEditor.titleWithoutReturn(_ title: String) -> String?`; `NoteBlockKind.barOrder: [NoteBlockKind]`, `NoteBlockKind.moreOrder: [NoteBlockKind]`, `NoteBlockKind.chipTitle: String`. Task 3 consumes all of them.

- [ ] **Step 1: Write the failing tests**

Append inside the `NoteBlockEditorTests` suite (before its closing brace):

```swift
    // MARK: - The bar's pick

    @Test func changingTheKindKeepsTheWords() {
        let line = NoteBlock(text: "Buy oat milk")
        let result = NoteBlockEditor.changeKind(doc(line), at: line.id, to: .todo)

        #expect(result.handled)
        #expect(result.blocks[0].kind == .todo)
        #expect(result.blocks[0].text == "Buy oat milk")
        #expect(result.focus == line.id)
    }

    @Test func changingToARuleKeepsACaretBelow() {
        let line = NoteBlock(text: "Section")
        let result = NoteBlockEditor.changeKind(doc(line), at: line.id, to: .divider)

        #expect(result.blocks.map(\.kind) == [.divider, .paragraph])
        #expect(result.focus == result.blocks[1].id)
    }

    @Test func changingTheKindOfAMissingBlockDoesNothing() {
        let line = NoteBlock(text: "Here")
        let result = NoteBlockEditor.changeKind(doc(line), at: UUID(), to: .todo)

        #expect(!result.handled)
        #expect(result.blocks == doc(line))
    }

    // MARK: - The title's Return

    @Test func aReturnTypedInTheTitleIsStrippedAndNoticed() {
        #expect(NoteBlockEditor.titleWithoutReturn("Weekend\n") == "Weekend")
        #expect(NoteBlockEditor.titleWithoutReturn("Week\nend reset") == "Weekend reset")
        #expect(NoteBlockEditor.titleWithoutReturn("Weekend reset") == nil)
        #expect(NoteBlockEditor.titleWithoutReturn("\n") == "")
    }
```

Append inside the `NoteBlockTests` suite:

```swift
    @Test func thePickerReachesEveryKindOnce() {
        let all = NoteBlockKind.barOrder + NoteBlockKind.moreOrder
        #expect(all.count == NoteBlockKind.allCases.count)
        #expect(Set(all) == Set(NoteBlockKind.allCases))
        #expect(NoteBlockKind.barOrder.map(\.chipTitle) == ["Text", "To-do", "Heading", "Bullet", "Numbered", "Quote"])
        #expect(NoteBlockKind.moreOrder.map(\.chipTitle) == ["Heading 2", "Heading 3", "Callout", "Code", "Sketch", "Divider"])
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter "NoteBlockEditorTests|NoteBlockTests"`
Expected: compile errors, `type 'NoteBlockEditor' has no member 'changeKind'`, `no member 'titleWithoutReturn'`, `type 'NoteBlockKind' has no member 'barOrder'`.

- [ ] **Step 3: Write the rules**

In `NoteBlockEditor.swift`, after `transform(_:at:to:text:)` (it ends with `return Result(blocks: blocks, focus: id)` and a closing brace), add:

```swift
    /// A kind picked from the bar for a block that already has words: the
    /// kind changes, the words stay. The slash menu's pick goes through
    /// `transform` with an empty string instead, since what was typed there
    /// was a command rather than content.
    public static func changeKind(_ blocks: [NoteBlock], at id: UUID, to kind: NoteBlockKind) -> Result {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return Result(blocks: blocks, handled: false)
        }
        return transform(blocks, at: id, to: kind, text: blocks[index].text)
    }

    /// The title field takes Return as a newline before the editor hears of
    /// it; the editor reads it as "go to the body". The title without its
    /// newlines when one was typed, nil when none was.
    public static func titleWithoutReturn(_ title: String) -> String? {
        guard title.contains(where: \.isNewline) else { return nil }
        return title.filter { !$0.isNewline }
    }
```

In `NoteBlock.swift`, after `menuOrder` (the `static var` returning the twelve kinds), add:

```swift
    /// The six kinds on the block picker's bar, in order, and the six behind
    /// its `More` menu. Together they are every kind once; a test holds
    /// them to it.
    public static var barOrder: [NoteBlockKind] {
        [.paragraph, .todo, .heading1, .bulleted, .numbered, .quote]
    }

    public static var moreOrder: [NoteBlockKind] {
        [.heading2, .heading3, .callout, .code, .sketch, .divider]
    }

    /// The word on a chip: shorter than the menu's title, so six fit a phone.
    public var chipTitle: String {
        switch self {
        case .paragraph: "Text"
        case .heading1:  "Heading"
        case .heading2:  "Heading 2"
        case .heading3:  "Heading 3"
        case .bulleted:  "Bullet"
        case .numbered:  "Numbered"
        case .todo:      "To-do"
        case .quote:     "Quote"
        case .callout:   "Callout"
        case .code:      "Code"
        case .divider:   "Divider"
        case .sketch:    "Sketch"
        }
    }
```

- [ ] **Step 4: Run the suites**

Run: `cd LifeOSKit && swift test --filter "NoteBlockEditorTests|NoteBlockTests"`
Expected: all pass, five more tests than before.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteBlockEditor.swift LifeOSKit/Sources/Persistence/NoteBlock.swift \
  LifeOSKit/Tests/PersistenceTests/NoteBlockEditorTests.swift LifeOSKit/Tests/PersistenceTests/NoteBlockTests.swift
git commit -m "feat(persistence): a kind change that keeps the words, the title's Return, and the picker's two rows

changeKind is the bar's pick, titleWithoutReturn reads a Return typed
into the vertical title field, and barOrder and moreOrder say which six
kinds sit on the bar and which six behind More."
```

---

### Task 2: Struck to-dos and the swipe

**Files:**
- Create: `LifeOSKit/Sources/DesignSystem/TodoSwipe.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/TodoSwipeTests.swift` (new)
- Modify: `LIfeOS/Features/Notes/View/BlockTextView.swift`, `LIfeOS/Features/Notes/View/NoteBlockRow.swift`

**Interfaces:**
- Produces: `TodoSwipe.minimum: CGFloat` (48) and `TodoSwipe.ticks(dx: CGFloat, dy: CGFloat) -> Bool`; `BlockTextView(... textColor: UIColor, strikethrough: Bool, ...)`.

- [ ] **Step 1: Write the failing test**

`LifeOSKit/Tests/DesignSystemTests/TodoSwipeTests.swift`:

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodoSwipeTests {
    @Test func aRightwardSwipeOfTheMinimumTicks() {
        #expect(TodoSwipe.ticks(dx: 48, dy: 0))
        #expect(TodoSwipe.ticks(dx: 90, dy: -20))
    }

    @Test func aShortOrLeftwardDragDoesNot() {
        #expect(!TodoSwipe.ticks(dx: 47, dy: 0))
        #expect(!TodoSwipe.ticks(dx: -60, dy: 0))
    }

    @Test func aScrollIsNotATick() {
        #expect(!TodoSwipe.ticks(dx: 50, dy: 80))
        #expect(!TodoSwipe.ticks(dx: 50, dy: -50))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter TodoSwipeTests`
Expected: compile error, `cannot find 'TodoSwipe' in scope`.

- [ ] **Step 3: Write the value**

`LifeOSKit/Sources/DesignSystem/TodoSwipe.swift`:

```swift
import Foundation

/// Whether a drag across a to-do row is the tick gesture: at least 48pt to
/// the right, and more sideways than up or down, so a scroll that starts on
/// a to-do never ticks it. The same rule the calendar's day swipe uses to
/// tell a page turn from a scroll.
public enum TodoSwipe {
    public static let minimum: CGFloat = 48

    public static func ticks(dx: CGFloat, dy: CGFloat) -> Bool {
        dx >= minimum && abs(dx) > abs(dy)
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `cd LifeOSKit && swift test --filter TodoSwipeTests`
Expected: `3 tests ... passed`.

- [ ] **Step 5: The text view learns to strike**

In `BlockTextView.swift`:

(a) After `let textColor: UIColor` (line 63), add:

```swift
    /// A checked to-do: struck through in the quiet colour. An attribute on
    /// the whole buffer, so typing into a struck line stays struck.
    let strikethrough: Bool
```

(b) `apply` and `restyle` on the `Coordinator` gain the flag and pass it on. Replace their signatures and bodies:

```swift
        func apply(text: String, to view: BlockUITextView, kind: NoteBlockKind, linkColor: UIColor,
                   textColor: UIColor, strikethrough: Bool) {
            view.attributedText = Coordinator.attributed(
                text, kind: kind, linkColor: linkColor, textColor: textColor, strikethrough: strikethrough
            )
            view.appliedKind = kind
            view.appliedTextColor = textColor
            view.appliedStrikethrough = strikethrough
        }

        func restyle(_ view: BlockUITextView, kind: NoteBlockKind, linkColor: UIColor,
                     textColor: UIColor, strikethrough: Bool) {
            guard view.appliedKind != kind || view.appliedTextColor != textColor
                    || view.appliedStrikethrough != strikethrough else { return }
            let selection = view.selectedRange
            view.attributedText = Coordinator.attributed(
                view.text, kind: kind, linkColor: linkColor, textColor: textColor, strikethrough: strikethrough
            )
            view.selectedRange = selection
            view.appliedKind = kind
            view.appliedTextColor = textColor
            view.appliedStrikethrough = strikethrough
        }
```

If the existing `apply` or `restyle` body has lines these replacements do not show (read them first at lines 144 to 160), keep those lines; the change is the extra parameter, the extra guard clause and the extra `applied` assignment.

(c) `attributed(_:kind:linkColor:textColor:)` becomes `attributed(_:kind:linkColor:textColor:strikethrough:)`; in its base attributes dictionary (the one with `.font`, `.foregroundColor`, `.paragraphStyle`), build the dictionary first so the strike can be added:

```swift
            var base: [NSAttributedString.Key: Any] = [
                .font: BlockStyle.font(kind),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
            ]
            if strikethrough {
                base[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                base[.strikethroughColor] = textColor
            }
            let attributed = NSMutableAttributedString(string: text, attributes: base)
```

(d) On `BlockUITextView`, after `var appliedTextColor: UIColor?` (line 246), add `var appliedStrikethrough = false`. Every call of `apply(...)` and `restyle(...)` in `makeUIView` (line 102) and `updateUIView` (lines 114 and 120) passes `strikethrough: strikethrough`. The text view's `typingAttributes` follow the attributed text UIKit already holds, so a struck line stays struck as the person types.

- [ ] **Step 6: The row**

In `NoteBlockRow.swift`:

(a) Replace the `textColor` doc comment and property (lines 37 to 41) with:

```swift
    /// Done to-dos go quiet and struck through: the box says it, and so does
    /// the line, which is what makes a long list scannable.
    private var isStruck: Bool { block.kind == .todo && block.isChecked }
    private var textColor: Color { isStruck ? secondary : primary }
```

(b) In the `.todo` gutter case, the mark is ink when checked, not the accent:

```swift
                    .foregroundStyle(block.isChecked ? primary : secondary)
```

(c) `textView` passes `strikethrough: isStruck` after `textColor: UIColor(textColor),`.

(d) The text row (the `HStack(alignment: .top, spacing: 8)` branch) gains the swipe and its haptic. After `.background(ground)` add:

```swift
            .gesture(block.kind == .todo ? tickSwipe : nil)
            .sensoryFeedback(.impact(weight: .light), trigger: block.isChecked)
```

and, after `indentWidth`, add:

```swift
    /// A swipe to the right ticks a to-do; a scroll that starts on one does
    /// not. The gesture sits under the scroll view's, so a vertical drag goes
    /// to the page and only a sideways one reaches here.
    private var tickSwipe: some Gesture {
        DragGesture(minimumDistance: TodoSwipe.minimum)
            .onEnded { value in
                guard TodoSwipe.ticks(dx: value.translation.width, dy: value.translation.height) else { return }
                onToggleCheck()
            }
    }
```

`.gesture(_:)` takes an optional gesture, so a non-to-do row carries none.

- [ ] **Step 7: Build the app**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task2.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task2.log | head -5
```

Expected: `build exit 0`. If `.gesture` refuses an optional, write `.gesture(tickSwipe, isEnabled: block.kind == .todo)` instead (iOS 18 and later).

- [ ] **Step 8: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/TodoSwipe.swift LifeOSKit/Tests/DesignSystemTests/TodoSwipeTests.swift \
  LIfeOS/Features/Notes/View/BlockTextView.swift LIfeOS/Features/Notes/View/NoteBlockRow.swift
git commit -m "feat(notes): a checked to-do is struck through, and a swipe right ticks it

The text view strikes the whole buffer so typing into a done line stays
done; the gutter mark is ink, not the accent; TodoSwipe decides when a
drag is the tick and when it is a scroll."
```

---

### Task 3: The block picker and the title's Return

**Files:**
- Create: `LIfeOS/Features/Notes/View/NoteBlockPicker.swift`
- Modify: `LIfeOS/Features/Notes/View/NoteAccessoryBar.swift`, `LIfeOS/Features/Notes/ViewModel/NoteEditorViewModel.swift`, `LIfeOS/Features/Notes/View/NoteEditorScreen.swift`

**Interfaces:**
- Consumes: Task 1's `changeKind`, `titleWithoutReturn`, `barOrder`, `moreOrder`, `chipTitle`.
- Produces: `NoteBlockPicker(currentKind:isInking:onPick:onIndent:onToggleInk:)`; `NoteAccessoryBar` gains `onChangeKind: (NoteBlockKind) -> Void`; on the view model `pickBlockKind(_:)` and `submitTitle()`.

- [ ] **Step 1: The picker**

```swift
import SwiftUI
import DesignSystem
import Persistence

/// The row above the keyboard: six kinds as labelled chips, the rest behind
/// `More`, then Indent, Outdent and Draw. The current kind is the one filled
/// chip, so a person can see what the block they are in already is before
/// they change it. `Hide keyboard` stays outside, pinned by the bar.
struct NoteBlockPicker: View {
    let currentKind: NoteBlockKind
    var isInking: Bool
    var onPick: (NoteBlockKind) -> Void
    var onIndent: (Int) -> Void
    var onToggleInk: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.x1) {
                ForEach(NoteBlockKind.barOrder) { kind in
                    chip(kind)
                }
                Menu {
                    ForEach(NoteBlockKind.moreOrder) { kind in
                        Button(kind.title, systemImage: kind.systemImage) { onPick(kind) }
                    }
                } label: {
                    Label(NoteBlockKind.moreOrder.contains(currentKind) ? currentKind.chipTitle : "More",
                          systemImage: "ellipsis")
                }
                .buttonStyle(.editorial(NoteBlockKind.moreOrder.contains(currentKind) ? .primary : .secondary, size: .compact))
                .accessibilityLabel("More block types")
                Button { onIndent(1) } label: { Label("Indent", systemImage: "increase.indent") }
                    .buttonStyle(.editorial(.secondary, size: .compact))
                Button { onIndent(-1) } label: { Label("Outdent", systemImage: "decrease.indent") }
                    .buttonStyle(.editorial(.secondary, size: .compact))
                Button(action: onToggleInk) {
                    Label(isInking ? "Stop drawing" : "Draw", systemImage: "scribble.variable")
                }
                .buttonStyle(.editorial(isInking ? .primary : .secondary, size: .compact))
            }
            .font(LifeOSType.label)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ kind: NoteBlockKind) -> some View {
        Button { onPick(kind) } label: {
            Label(kind.chipTitle, systemImage: kind.systemImage)
        }
        .buttonStyle(.editorial(kind == currentKind ? .primary : .secondary, size: .compact))
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(kind == currentKind ? [.isSelected] : [])
    }
}
```

- [ ] **Step 2: The bar**

In `NoteAccessoryBar.swift`:

(a) After `var onPickBlock: (NoteBlockKind) -> Void` (line 17), add:

```swift
    /// The bar's pick: the block keeps its words. The slash menu's pick above
    /// does not, which is why they are two callbacks.
    var onChangeKind: (NoteBlockKind) -> Void
```

(b) Replace the whole `formattingBar` (the `// MARK: - Formatting bar` section, lines 143 to 202) with:

```swift
    // MARK: - Block picker

    private var formattingBar: some View {
        HStack(spacing: 0) {
            NoteBlockPicker(
                currentKind: currentKind,
                isInking: isInking,
                onPick: onChangeKind,
                onIndent: onIndent,
                onToggleInk: onToggleInk
            )

            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(LifeOSType.secondary.weight(.medium))
                    .foregroundStyle(primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Hide keyboard")
        }
    }
```

- [ ] **Step 3: The view model**

In `NoteEditorViewModel.swift`, after `applySlashCommand(_:)`, add:

```swift
    /// The bar's pick: the focused block changes kind and keeps its words.
    /// A rule or a sketch still gets a paragraph below for the caret.
    func pickBlockKind(_ kind: NoteBlockKind) {
        guard let id = focusedBlockID else { return }
        let result = NoteBlockEditor.changeKind(blocks, at: id, to: kind)
        guard result.handled else { return }
        blocks = result.blocks
        if let focus = result.focus { focusedBlockID = focus }
        slashQuery = nil
        scheduleSave()
    }

    /// Return in the title. The vertical field has already put a newline
    /// into the text by the time this runs, so the title is read back
    /// without it, and the caret goes to the first block.
    func submitTitle() {
        if let stripped = NoteBlockEditor.titleWithoutReturn(title) { title = stripped }
        focusedBlockID = blocks.first?.id
    }
```

- [ ] **Step 4: The screen**

In `NoteEditorScreen.swift`:

(a) The accessory bar call gains, after `onPickBlock: { model.applySlashCommand($0) },`:

```swift
                    onChangeKind: { model.pickBlockKind($0) },
```

(b) The title field (the `TextField("Untitled", text: $model.title, axis: .vertical)` with `.focused($titleFocused)`) gains, after `.focused($titleFocused)`:

```swift
                .submitLabel(.next)
                .onSubmit { leaveTitle() }
                // A vertical field puts Return into the text instead of
                // submitting; the editor takes the hint and moves on.
                .onChange(of: model.title) { _, title in
                    if title.contains(where: \.isNewline) { leaveTitle() }
                }
```

(c) On the screen root, next to the `.onAppear` that handles `focusOnAppear`, add:

```swift
        .onChange(of: model.focusedBlockID) { _, id in
            if id != nil { titleFocused = false }
        }
```

(d) After `private var focusedKind: NoteBlockKind { ... }`, add:

```swift
    private func leaveTitle() {
        titleFocused = false
        model.submitTitle()
    }
```

- [ ] **Step 5: Build the app**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task3.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task3.log | head -5
```

Expected: `build exit 0`.

- [ ] **Step 6: Commit**

```bash
git add LIfeOS/Features/Notes/View/NoteBlockPicker.swift LIfeOS/Features/Notes/View/NoteAccessoryBar.swift \
  LIfeOS/Features/Notes/ViewModel/NoteEditorViewModel.swift LIfeOS/Features/Notes/View/NoteEditorScreen.swift
git commit -m "feat(notes): a labelled block picker above the keyboard, and Return from the title into the body

Six kinds as chips with the current one filled, the rest behind More,
then Indent, Outdent and Draw; a pick keeps the block's words. The
title's Return lands the caret in the first block."
```

---

### Task 4: Preview pages, gates and captures

**Files:**
- Modify: `LIfeOS/Features/Notes/View/NotesDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`

- [ ] **Step 1: The pages**

In `NotesDesignPreview.swift`, the `switch page` gains two cases before `default:`:

```swift
            case "notes-editor":
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, onOpenLinked: { _ in })
                }
            case "notes-editor-picker":
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, focusOnAppear: .firstBlock, onOpenLinked: { _ in })
                }
```

and the doc comment on `page` reads: `` `notes-editor-new`: a blank page with the title focused; `notes-editor`: the sample page, nothing focused; `notes-editor-picker`: its first block focused, the picker up; `notes-filing`: the sample page with the filing sheet up. ``

In `HealthActivityDesignPreview.swift`, the Notes line becomes:

```swift
            else if ["notes-editor-new", "notes-filing", "notes-editor", "notes-editor-picker"].contains(page) { NotesDesignPreview(page: page) }
```

- [ ] **Step 2: Tests, typography and the build**

```bash
(cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*(Test run with|recorded an issue)" | tail -2)
scripts/check-typography.sh > $OUT/typo-editor.txt 2>&1
diff <(sed -E 's/^([^:]*):[0-9]+:/\1:/' $OUT/typo-editor-base.txt | sort) <(sed -E 's/^([^:]*):[0-9]+:/\1:/' $OUT/typo-editor.txt | sort) | grep '^>' || echo "typography: no new violations"
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task4.log 2>&1; echo "build exit $?"
```

Expected: the suite passes with eight new tests (`NoteBlockEditorTests` 4, `NoteBlockTests` 1, `TodoSwipeTests` 3), no new violations, `build exit 0`.

- [ ] **Step 3: Captures**

```bash
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/notes-editor/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=B192EA65-BAA2-4814-A298-94A2F0C8FC87
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
capture() { local name=$1; shift
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot "$OUT/pr-editor-$name.png" >/dev/null; }
capture page --page=notes-editor
capture page-dark --page=notes-editor --dark
capture picker --page=notes-editor-picker
capture picker-dark --page=notes-editor-picker --dark
capture new --page=notes-editor-new
ls -la $OUT/pr-editor-*.png
```

Check each with the Read tool:
- `page`: `Weekend reset` with its chip `Areas · Personal`; under `Make time for`, `Walk somewhere new` struck through in quiet ink with an ink checkmark box, `Book a quiet hour to read` plain with a quiet empty box; no keyboard.
- `picker`: the keyboard up, the caret in the first paragraph, and above the keyboard a row of chips reading `Text` (filled), `To-do`, `Heading`, `Bullet`, `Numbered`, `Quote`, `More`, `Indent`, `Outdent`, `Draw`, with the hide-keyboard glyph pinned at the right. Nothing in the accent colour.
- `new`: unchanged from PR 1 apart from the Return key reading `next`.
- Both dark pages: paper and ink inverted, the struck line still legible.

- [ ] **Step 4: Simulator checks**

From `--page=notes-editor`: swipe right across `Book a quiet hour to read` and screenshot (struck). From `--page=notes-editor-picker`: tap `To-do` and screenshot (the first paragraph is now a to-do with its words, `To-do` filled). From `--page=notes-editor-new`: type `Weekend`, press Return, screenshot (the caret in the body, the title `Weekend` without a blank line). Use the recipe in the simulator memory; if two taps in a row leave the screen unchanged, stop and say so in the PR.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Notes/View/NotesDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(notes): preview pages for the struck page and the block picker"
```

---

### Task 5: Open the pull request

- [ ] **Step 1: Rebase, re-run, push**

```bash
git fetch origin && git rebase origin/main && (cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*Test run with" | tail -1)
git push -u origin feat/notes-editor
```

- [ ] **Step 2: The PR**

`gh pr create --base main --title "feat(notes): a labelled block picker, struck to-dos, and Return from the title into the body" --body-file $OUT/pr-editor-body.md`, the body in the house style (`## Summary`, `## Verification`, `## Deferred minors`, the spec and plan paths, PR 2 of 3). No attribution footer.

- [ ] **Step 3: Memory**

Update `day-briefing-and-notes-brainstorm.md`: PR 2 of the Notes work is PR #N; next is the walkthrough plan (spec section 3).
