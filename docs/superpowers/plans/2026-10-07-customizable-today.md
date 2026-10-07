# Customizable Today Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Today becomes a set of modules the person arranges in place (long-press, wobble, drag, hide, add), in two columns on iPad and one on a phone, including Today's tasks (with overdue), GitHub, Weather, Spent today and From LIFO.

**Architecture:** The layout is a tested value in `DesignSystem` (`TodayModule`, `TodayLayout`, `TodayRow`): two ordered columns, hide/add/move, phone order, tile pairing, tolerant decoding. `DayChecklist` in `Persistence` gains overdue tasks for today. In the app, `TodayLayoutStore` (an `@Observable` over the account's defaults) holds the layout, the arranging flag and the hint flag; `TodayScreen` draws `TodayLayout` instead of a fixed body, hosting a `DayViewModel` for today that loads only what visible modules need; arranging adds the wobble, minus buttons, drag and drop of `rawValue` strings, the Add tray, Done and Reset, plus VoiceOver actions.

**Tech Stack:** SwiftUI (`draggable`/`dropDestination` with `String`, `accessibilityAction`, `sensoryFeedback`), Observation, Swift Testing in `LifeOSKit`, XCUITest in `LIfeOSUITests`.

**Spec:** `docs/superpowers/specs/2026-10-07-customizable-today-design.md`

## Global Constraints

- Module names and titles, verbatim: `nextUp` Next up, `month` Month, `tasks` Today's tasks, `github` GitHub, `scheduledWorkout` Scheduled workout, `steps` Steps, `sleep` Sleep, `weight` Weight, `recovery` Recovery, `weather` Weather, `spentToday` Spent today, `fromLifo` From LIFO.
- Default: left `nextUp, month, tasks, scheduledWorkout`; right `steps, sleep, weight, recovery`; hidden `github, weather, spentToday, fromLifo`.
- Saved as JSON under `today.layout` in `UserDefaults.currentAccount`; flags `today.layout.githubOffered`, `today.layout.hintSeen`.
- Copy, verbatim: `Arranging Today`, `Done`, `Add to Today`, `Reset to default`, `Hide <title>`, `Add <title>`, `Move up`, `Move down`, `Move to other column`, `Long-press anything to rearrange Today.`, `Today's tasks`, `Nothing planned. Add a task below.`, `Add a task`, `overdue · <page title>`, `Nothing spent`, `Nothing from LIFO`.
- Long-press 0.5 s with a light haptic enters arranging; the masthead stays fixed and is not a module.
- Wobble ±1.2°, alternating phase; with Reduce Motion a dashed hairline outline instead.
- Paper, ink, hairlines, quiet ink; buttons `.editorial(role)` or `.plain`; fonts only from `LifeOSType`/`Editorial`. `scripts/check-typography.sh` reports nothing new (line numbers stripped).
- `LifeOSKit` builds for macOS 26: no UIKit in `DesignSystem` or `Persistence`.
- Overdue tasks appear for today only (Today and the day screen for today), never on other days.
- Commits: conventional, no em dashes, no Claude attribution. Worktree `/Users/shivvyas/LIfeOS/.claude/worktrees/today-layout` on `feat/today-layout` from main 70532ef. Simulator `B192EA65-BAA2-4814-A298-94A2F0C8FC87`; iPad simulator `90F31CB7-2D45-488A-A9E0-8F8CC597B3B9`; DerivedData `~/Library/Developer/Xcode/DerivedData/today-layout`. `$W` is the ledger workspace.

## Review Focus

1. A saved layout from an older build that lacks a module added later (Inbox) must keep that module hidden, and a name this build does not know must be dropped, not crash: `TodayLayoutTests.decodingKeepsNewModulesHiddenAndDropsUnknownOnes` in Task 1.
2. Hiding the last module of a column and adding it back must not lose it or duplicate it: `TodayLayoutTests.hideThenAddRoundTrips` in Task 1.
3. An overdue task on an archived page or already ticked must not appear: `DayChecklistTests.overdueSkipsDoneTasks` in Task 2 and the archived-page filter in Task 3.
4. Hiding Weather must mean no location request and no forecast call; the `DayViewModel` override drops `.weather` from its sections: `TodayModuleSectionsTests.hiddenModulesLoadNothing` in Task 1.
5. A tap while arranging must not tick a task or open a day; checked by the UI test in Task 6 (tap a task row while arranging, it stays unticked).

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/DesignSystem/TodayLayout.swift` (new) | `TodayModule`, `TodayLayout`, `TodayRow`, `TodayModule.daySection` |
| `LifeOSKit/Tests/DesignSystemTests/TodayLayoutTests.swift` (new) | Its tests |
| `LifeOSKit/Sources/Persistence/DayChecklist.swift`, `NotesStore.swift` | Overdue rows; `tasks(dueBefore:)` |
| `LifeOSKit/Tests/PersistenceTests/DayChecklistTests.swift`, `NotesStoreTests.swift` | Their tests |
| `LIfeOS/Features/Day/ViewModel/DayViewModel.swift` | `onlySections` override; overdue tasks in the checklist |
| `LIfeOS/Features/Today/Model/TodayLayoutStore.swift` (new) | The saved layout, arranging and hint flags |
| `LIfeOS/Features/Today/View/TodayScreen.swift` | Draws the layout; hosts the day model |
| `LIfeOS/Features/Today/View/TodayModules.swift` (new) | Each module's view and the tile pair |
| `LIfeOS/Features/Today/View/TodayArranging.swift` (new) | Wobble, minus, drop, tray, hint |
| `LIfeOS/App/RootView.swift` | Passes the new callbacks |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift`, `Health/View/HealthActivityDesignPreview.swift` | Pages `today-custom`, `today-arranging`, `today-ipad-custom` |
| `LIfeOSUITests/TodayLayoutUITests.swift` (new) | Arrange, hide, add, tap-guard |

---

### Task 0: Worktree and baselines

- [ ] `cd` the worktree; `ls Config/Secrets.xcconfig`; `(cd LifeOSKit && swift test 2>&1 | grep "Test run with" | tail -1)` (expect 1567 in 224 suites); `scripts/check-typography.sh 2>&1 | sed -E 's/:[0-9]+:/:/' | sort > $W/typo-base.txt`; commit this plan: `git commit -m "docs(plans): a Today you arrange"`.

---

### Task 1: The layout value

**Files:** Create `LifeOSKit/Sources/DesignSystem/TodayLayout.swift`, `LifeOSKit/Tests/DesignSystemTests/TodayLayoutTests.swift`.

**Interfaces — Produces:** `TodayModule: String, CaseIterable, Codable, Sendable` with `title: String`, `isTile: Bool`, `daySection: DaySection?` (`tasks`→`.checklist`, `weather`→`.weather`, `spentToday`→`.money`, `fromLifo`→`.nudges`, `github`→`.project`, others nil); `TodayColumn { case left, right }`; `TodayRow: Equatable, Identifiable { case single(TodayModule); case pair(TodayModule, TodayModule?) }`; `TodayLayout: Equatable, Sendable` with `left`, `right`, `hidden: [TodayModule]` (in `allCases` order), `static let standard`, `phoneOrder`, `column(of:) -> TodayColumn?`, `move(_:to:at:)`, `hide(_:)`, `add(_:to:)`, `add(_:)`, `moveUp(_:)`, `moveDown(_:)`, `moveToOtherColumn(_:)`, `offerGitHub()`, `static func rows(_ modules: [TodayModule]) -> [TodayRow]`, `encoded() -> Data`, `static func decoded(_ data: Data?) -> TodayLayout`, `static func sections(for visible: [TodayModule]) -> Set<DaySection>`.

- [ ] **Step 1: Failing tests.**

```swift
import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodayLayoutTests {
    @Test func theDefaultIsTheIPadEstate() {
        let layout = TodayLayout.standard
        #expect(layout.left == [.nextUp, .month, .tasks, .scheduledWorkout])
        #expect(layout.right == [.steps, .sleep, .weight, .recovery])
        #expect(layout.hidden == [.github, .weather, .spentToday, .fromLifo])
        #expect(layout.phoneOrder == layout.left + layout.right)
    }

    @Test func moveWithinAndAcross() {
        var layout = TodayLayout.standard
        layout.move(.month, to: .left, at: 0)
        #expect(layout.left == [.month, .nextUp, .tasks, .scheduledWorkout])
        layout.move(.tasks, to: .right, at: 1)
        #expect(layout.left == [.month, .nextUp, .scheduledWorkout])
        #expect(layout.right == [.steps, .tasks, .sleep, .weight, .recovery])
        layout.move(.weather, to: .left, at: 99)
        #expect(layout.left.last == .weather)
    }

    @Test func hideThenAddRoundTrips() {
        var layout = TodayLayout(left: [.nextUp], right: [])
        layout.hide(.nextUp)
        #expect(layout.left.isEmpty)
        #expect(layout.hidden.contains(.nextUp))
        layout.add(.nextUp, to: .left)
        layout.add(.nextUp, to: .right)
        #expect(layout.left == [.nextUp])
        #expect(layout.right.isEmpty)
    }

    @Test func addPicksTheShorterColumnCountingTilesAsHalf() {
        var layout = TodayLayout(left: [.nextUp, .month], right: [.steps, .sleep, .weight])
        layout.add(.weather)
        #expect(layout.right.last == .weather)
        var other = TodayLayout(left: [.nextUp], right: [.month, .tasks])
        other.add(.weather)
        #expect(other.left.last == .weather)
    }

    @Test func moveUpAndDownCrossTheColumns() {
        var layout = TodayLayout(left: [.nextUp, .month], right: [.steps, .sleep])
        layout.moveDown(.month)
        #expect(layout.left == [.nextUp])
        #expect(layout.right == [.month, .steps, .sleep])
        layout.moveUp(.month)
        #expect(layout.left == [.nextUp, .month])
        layout.moveUp(.nextUp)
        #expect(layout.left == [.nextUp, .month])
        layout.moveToOtherColumn(.nextUp)
        #expect(layout.right.first == .nextUp)
    }

    @Test func adjacentTilesPairUp() {
        #expect(TodayLayout.rows([.month, .steps, .sleep, .weight, .nextUp, .recovery])
                == [.single(.month), .pair(.steps, .sleep), .pair(.weight, nil), .single(.nextUp), .pair(.recovery, nil)])
    }

    @Test func decodingKeepsNewModulesHiddenAndDropsUnknownOnes() {
        let data = Data(#"{"left":["month","inbox","nextUp"],"right":["steps"]}"#.utf8)
        let layout = TodayLayout.decoded(data)
        #expect(layout.left == [.month, .nextUp])
        #expect(layout.right == [.steps])
        #expect(layout.hidden.contains(.tasks))
    }

    @Test func aModuleSavedTwiceIsKeptOnce() {
        let data = Data(#"{"left":["month"],"right":["month","steps"]}"#.utf8)
        let layout = TodayLayout.decoded(data)
        #expect(layout.left == [.month])
        #expect(layout.right == [.steps])
    }

    @Test func nothingSavedIsTheDefaultAndItRoundTrips() {
        #expect(TodayLayout.decoded(nil) == .standard)
        var layout = TodayLayout.standard
        layout.move(.month, to: .left, at: 0)
        #expect(TodayLayout.decoded(layout.encoded()) == layout)
    }

    @Test func gitHubIsOfferedOnceToTheLeft() {
        var layout = TodayLayout.standard
        layout.offerGitHub()
        layout.offerGitHub()
        #expect(layout.left.filter { $0 == .github }.count == 1)
        #expect(layout.left.last == .github)
    }

    @Test func titlesAndTiles() {
        #expect(TodayModule.tasks.title == "Today's tasks")
        #expect(TodayModule.fromLifo.title == "From LIFO")
        #expect(TodayModule.allCases.filter(\.isTile) == [.steps, .sleep, .weight, .recovery])
    }
}

@Suite struct TodayModuleSectionsTests {
    @Test func hiddenModulesLoadNothing() {
        #expect(TodayLayout.sections(for: [.nextUp, .month, .tasks]) == [.checklist])
        #expect(TodayLayout.sections(for: [.weather, .github, .spentToday, .fromLifo]) == [.weather, .project, .money, .nudges])
    }
}
```

- [ ] **Step 2:** `cd LifeOSKit && swift test --filter "TodayLayout|TodayModuleSections"` → build fails (`TodayLayout` missing).

- [ ] **Step 3: Implement** `TodayLayout.swift`:

```swift
import Foundation

/// A piece of Today the person can place, hide or bring back.
public enum TodayModule: String, CaseIterable, Codable, Sendable {
    case nextUp, month, tasks, github, scheduledWorkout, steps, sleep, weight, recovery, weather, spentToday, fromLifo

    public var title: String {
        switch self {
        case .nextUp: "Next up"
        case .month: "Month"
        case .tasks: "Today's tasks"
        case .github: "GitHub"
        case .scheduledWorkout: "Scheduled workout"
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .weight: "Weight"
        case .recovery: "Recovery"
        case .weather: "Weather"
        case .spentToday: "Spent today"
        case .fromLifo: "From LIFO"
        }
    }

    public var isTile: Bool { [.steps, .sleep, .weight, .recovery].contains(self) }

    /// What the day's model must load for this module; nil when Today reads
    /// it from its own snapshot.
    public var daySection: DaySection? {
        switch self {
        case .tasks: .checklist
        case .weather: .weather
        case .spentToday: .money
        case .fromLifo: .nudges
        case .github: .project
        default: nil
        }
    }
}

public enum TodayColumn: Sendable { case left, right }

/// One line of Today: a module, or two tiles side by side.
public enum TodayRow: Equatable, Identifiable, Sendable {
    case single(TodayModule)
    case pair(TodayModule, TodayModule?)

    public var id: String {
        switch self {
        case .single(let module): module.rawValue
        case .pair(let first, let second): "\(first.rawValue)+\(second?.rawValue ?? "")"
        }
    }
}

/// Today's arrangement: two columns, each in order. The phone reads the left
/// then the right as one list. Anything in neither is hidden, in the tray.
public struct TodayLayout: Equatable, Sendable {
    public private(set) var left: [TodayModule]
    public private(set) var right: [TodayModule]

    public init(left: [TodayModule], right: [TodayModule]) {
        var seen = Set<TodayModule>()
        self.left = left.filter { seen.insert($0).inserted }
        self.right = right.filter { seen.insert($0).inserted }
    }

    /// The approved iPad estate arrangement; GitHub, Weather, Spent today and
    /// From LIFO wait in the tray.
    public static let standard = TodayLayout(left: [.nextUp, .month, .tasks, .scheduledWorkout],
                                             right: [.steps, .sleep, .weight, .recovery])

    public var hidden: [TodayModule] { TodayModule.allCases.filter { column(of: $0) == nil } }
    public var phoneOrder: [TodayModule] { left + right }

    public func column(of module: TodayModule) -> TodayColumn? {
        if left.contains(module) { return .left }
        if right.contains(module) { return .right }
        return nil
    }

    public mutating func move(_ module: TodayModule, to column: TodayColumn, at index: Int) {
        left.removeAll { $0 == module }
        right.removeAll { $0 == module }
        switch column {
        case .left: left.insert(module, at: min(max(index, 0), left.count))
        case .right: right.insert(module, at: min(max(index, 0), right.count))
        }
    }

    public mutating func hide(_ module: TodayModule) {
        left.removeAll { $0 == module }
        right.removeAll { $0 == module }
    }

    /// A shown module stays where it is.
    public mutating func add(_ module: TodayModule, to column: TodayColumn) {
        guard self.column(of: module) == nil else { return }
        move(module, to: column, at: .max)
    }

    /// To the shorter column, a tile counting as half a module.
    public mutating func add(_ module: TodayModule) {
        func weight(_ modules: [TodayModule]) -> Double { modules.reduce(0) { $0 + ($1.isTile ? 0.5 : 1) } }
        add(module, to: weight(right) < weight(left) ? .right : .left)
    }

    /// One step through the phone order, crossing between the columns.
    public mutating func moveUp(_ module: TodayModule) {
        if let index = left.firstIndex(of: module) {
            if index > 0 { left.swapAt(index, index - 1) }
        } else if let index = right.firstIndex(of: module) {
            if index > 0 { right.swapAt(index, index - 1) } else { move(module, to: .left, at: .max) }
        }
    }

    public mutating func moveDown(_ module: TodayModule) {
        if let index = right.firstIndex(of: module) {
            if index < right.count - 1 { right.swapAt(index, index + 1) }
        } else if let index = left.firstIndex(of: module) {
            if index < left.count - 1 { left.swapAt(index, index + 1) } else { move(module, to: .right, at: 0) }
        }
    }

    public mutating func moveToOtherColumn(_ module: TodayModule) {
        switch column(of: module) {
        case .left: move(module, to: .right, at: 0)
        case .right: move(module, to: .left, at: 0)
        case nil: break
        }
    }

    /// The first time GitHub connects, its card joins the left column.
    public mutating func offerGitHub() { add(.github, to: .left) }

    /// Consecutive tiles share a row, two at a time.
    public static func rows(_ modules: [TodayModule]) -> [TodayRow] {
        var rows: [TodayRow] = []
        var pending: TodayModule?
        for module in modules {
            if module.isTile {
                if let first = pending { rows.append(.pair(first, module)); pending = nil } else { pending = module }
            } else {
                if let first = pending { rows.append(.pair(first, nil)); pending = nil }
                rows.append(.single(module))
            }
        }
        if let first = pending { rows.append(.pair(first, nil)) }
        return rows
    }

    /// What the day's model loads for the modules on screen.
    public static func sections(for visible: [TodayModule]) -> Set<DaySection> {
        Set(visible.compactMap(\.daySection))
    }

    private struct Stored: Codable { var left: [String]; var right: [String] }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(Stored(left: left.map(\.rawValue), right: right.map(\.rawValue)))) ?? Data()
    }

    /// Names this build does not know are dropped; modules the saved layout
    /// never had stay hidden; nothing saved is the default.
    public static func decoded(_ data: Data?) -> TodayLayout {
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .standard }
        return TodayLayout(left: stored.left.compactMap(TodayModule.init(rawValue:)),
                           right: stored.right.compactMap(TodayModule.init(rawValue:)))
    }
}
```

`DaySection` must be `Hashable` for the `Set`; it is `CaseIterable, Equatable, Sendable` — add `Hashable` to its declaration in `DayHeadline.swift` if the build complains.

- [ ] **Step 4:** the filter passes (12 tests); whole suite; `swift build`.
- [ ] **Step 5:** `git commit -m "feat(design): Today as two columns of modules, with moves, a tray and tile pairs"`

---

### Task 2: Overdue tasks for today

**Files:** Modify `LifeOSKit/Sources/Persistence/DayChecklist.swift`, `LifeOSKit/Sources/Persistence/NotesStore.swift` (after `tasks(dueOn:)`); Test `DayChecklistTests.swift`, `NotesStoreTests.swift`.

**Interfaces — Produces:** `DayChecklist.DueTask` gains `dueDate: Date?` (init parameter defaulting to nil); `DayChecklist.rows(...)` gains `overdue: [DueTask] = []` after `due:`; `NotesStore.tasks(dueBefore date: Date) throws -> [NoteTask]` (open only, due strictly before the start of `date`'s day).

- [ ] **Step 1: Failing tests.** Append to `DayChecklistTests`:

```swift
    private func task(_ text: String, daysAgo: Int, checked: Bool = false, page: String = "Health") -> DayChecklist.DueTask {
        DayChecklist.DueTask(documentID: UUID(), blockID: UUID(), text: text, isChecked: checked, pageTitle: page,
                             dueDate: day.addingTimeInterval(-86_400 * Double(daysAgo)))
    }

    @Test func overdueComesAfterTodaysDueOldestFirstOnTodayOnly() {
        let today = day.addingTimeInterval(3_600 * 9)
        let rows = DayChecklist.rows(
            journal: [], journalID: nil,
            due: [DayChecklist.DueTask(documentID: UUID(), blockID: UUID(), text: "Buy oat milk", isChecked: false, pageTitle: "Groceries")],
            overdue: [task("Call the dentist", daysAgo: 1), task("File taxes", daysAgo: 5, page: "Money")],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar, now: today)
        #expect(rows.map(\.text) == ["Buy oat milk", "File taxes", "Call the dentist"])
        #expect(rows[1].detail == "overdue · Money")
        let yesterday = DayChecklist.rows(
            journal: [], journalID: nil, due: [], overdue: [task("Call the dentist", daysAgo: 1)],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar, now: today.addingTimeInterval(86_400))
        #expect(yesterday.isEmpty)
    }

    @Test func overdueSkipsDoneTasks() {
        let rows = DayChecklist.rows(
            journal: [], journalID: nil, due: [], overdue: [task("Done already", daysAgo: 2, checked: true)],
            habits: [], ticked: [], day: day, editable: true, calendar: calendar, now: day.addingTimeInterval(3_600))
        #expect(rows.isEmpty)
    }
```

Append to `NotesStoreTests`:

```swift
    @Test func overdueTasksAreOpenAndBeforeToday() throws {
        let store = try makeStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 10))!
        let page = try store.createDocument(title: "Health", bucket: .areas, blocks: [
            NoteBlock(kind: .todo, text: "Late", dueDate: today.addingTimeInterval(-86_400)),
            NoteBlock(kind: .todo, text: "Late but done", isChecked: true, dueDate: today.addingTimeInterval(-86_400)),
            NoteBlock(kind: .todo, text: "Today", dueDate: today),
        ])
        try store.update(page, blocks: page.blocks)
        let overdue = try NotesStore(context: store.context, calendar: calendar).tasks(dueBefore: today)
        #expect(overdue.map(\.text) == ["Late"])
    }
```

(Check how `NotesStoreTests` reaches the context and indexes tasks: read `tasks(dueOn:)`'s existing test first, `grep -n "dueOn" LifeOSKit/Tests/PersistenceTests/*.swift`, and build the fixture the same way; adjust the two lines above to match.)

- [ ] **Step 2:** `swift test --filter "DayChecklist|NotesStoreTests"` → fails to build (`overdue:` and `dueDate:` unknown).

- [ ] **Step 3: Implement.** `DueTask`: add `public let dueDate: Date?` and the init parameter `dueDate: Date? = nil`. In `rows`, add parameter `overdue: [DueTask] = []` after `due:`, and after the due loop:

```swift
        // Late to-dos join today's list, oldest first; a past day is a record.
        if calendar.isDate(day, inSameDayAs: now) {
            let late = overdue.filter { !$0.isChecked && $0.documentID != journalID }
                .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            for task in late {
                rows.append(ChecklistRow(source: .page(documentID: task.documentID, blockID: task.blockID),
                                         text: task.text, detail: "overdue · \(task.pageTitle)",
                                         isDone: false, isEditable: editable))
            }
        }
```

`NotesStore`:

```swift
    /// Open to-dos due before the day began, across every page: today's
    /// overdue list.
    public func tasks(dueBefore date: Date) throws -> [NoteTask] {
        let day = calendar.startOfDay(for: date)
        return try indexedTasks(openOnly: true).filter { ($0.dueDate ?? .distantFuture) < day }
    }
```

(Use the real signature of the indexed-tasks reader above `tasks(dueOn:)`; it filters `openOnly`.)

- [ ] **Step 4:** filters pass; whole suite.
- [ ] **Step 5:** `git commit -m "feat(persistence): overdue to-dos join today's checklist"`

---

### Task 3: The day model loads only what is shown, and overdue

**Files:** Modify `LIfeOS/Features/Day/ViewModel/DayViewModel.swift`.

**Interfaces — Produces:** `DayViewModel.onlySections: Set<DaySection>?` (nil: everything the placement allows).

- [ ] **Step 1:** Add `var onlySections: Set<DaySection>?` and in `load()` replace `let sections = DaySections.visible(for: placement)` with:

```swift
        let sections = DaySections.visible(for: placement).filter { onlySections?.contains($0) ?? true }
```

- [ ] **Step 2:** In `loadChecklist`, build overdue rows (today only, live pages only) and pass them:

```swift
        let overdue: [DayChecklist.DueTask] = calendar.isDateInToday(date)
            ? try notes.tasks(dueBefore: date).compactMap { task in
                guard let page = try? notes.document(id: task.documentID), !page.isArchived else { return nil }
                return DayChecklist.DueTask(documentID: task.documentID, blockID: task.id, text: task.text,
                                            isChecked: task.isChecked, pageTitle: page.displayTitle, dueDate: task.dueDate)
            }
            : []
```

and `overdue: overdue` in the `DayChecklist.rows` call.

- [ ] **Step 3:** Build the app (`xcodebuild ... -derivedDataPath ~/Library/Developer/Xcode/DerivedData/today-layout build`), whole package suite, commit `feat(day): load only the sections asked for, and list overdue to-dos today`.

---

### Task 4: Today draws its layout

**Files:** Create `LIfeOS/Features/Today/Model/TodayLayoutStore.swift`, `LIfeOS/Features/Today/View/TodayModules.swift`; Modify `LIfeOS/Features/Today/View/TodayScreen.swift`, `LIfeOS/App/RootView.swift:430-440`.

**Interfaces — Produces:** `@MainActor @Observable final class TodayLayoutStore` with `init(defaults: UserDefaults = .currentAccount)`, `layout: TodayLayout` (setter saves), `isArranging: Bool`, `hintSeen: Bool` (setter saves), `update(_ change: (inout TodayLayout) -> Void)`, `reset()`, `offerGitHubOnce()`. `TodayScreen` gains `var layoutStore: TodayLayoutStore = TodayLayoutStore()` and `var onOpenSettings: () -> Void = {}`.

- [ ] **Step 1: The store.**

```swift
import Foundation
import Observation
import DesignSystem
import Persistence

/// Today's arrangement for this account on this device, saved on every change.
@MainActor @Observable
final class TodayLayoutStore {
    private let defaults: UserDefaults
    private static let key = "today.layout"
    private static let githubKey = "today.layout.githubOffered"
    private static let hintKey = "today.layout.hintSeen"

    var layout: TodayLayout { didSet { defaults.set(layout.encoded(), forKey: Self.key) } }
    var isArranging = false
    var hintSeen: Bool { didSet { defaults.set(hintSeen, forKey: Self.hintKey) } }

    init(defaults: UserDefaults = .currentAccount) {
        self.defaults = defaults
        layout = TodayLayout.decoded(defaults.data(forKey: Self.key))
        hintSeen = defaults.bool(forKey: Self.hintKey)
    }

    func update(_ change: (inout TodayLayout) -> Void) {
        var next = layout
        change(&next)
        layout = next
        hintSeen = true
    }

    func reset() { layout = .standard }

    /// The first time GitHub connects, once.
    func offerGitHubOnce() {
        guard !defaults.bool(forKey: Self.githubKey) else { return }
        defaults.set(true, forKey: Self.githubKey)
        update { $0.offerGitHub() }
    }
}
```

- [ ] **Step 2: Module views** (`TodayModules.swift`): a `TodayModuleView(module:snapshot:day:...)` switch drawing each module from the existing pieces. Move `masthead`, `healthPrompt`, `scheduledWorkout`, `agendaCard`, `month`, `tile(_:)` and the tile helpers out of `TodayScreen` into this file as functions of a `TodayModuleContext` value (the snapshot, `isHealthConnected`, the callbacks, the day model), keeping their code unchanged. New modules:
  - `tasks`: `EditorialSectionHeader(title: "Today's tasks") { "3 of 7" when non-empty }`, `ChecklistRows(rows:onTick:onOpen:)` with `onTick: day.tick`, `onOpen: { _ in onOpenToday() }` (the day screen opens pages), the empty line, and `HairlineField(text:placeholder: "Add a task", glyph: "plus", submitLabel: .done, onSubmit:)` calling `day.add`.
  - `github`: the `.project` state from `day.briefing?.project`: `EditorialSectionHeader(title: "Project")` with the repo, `ProjectRows(state:onOpen:onReconnect: onOpenSettings)`; nothing when nil (the arranging ghost is Task 5).
  - `weather`: `WeatherCard(state: day.briefing?.weather ?? .loading, isToday: true) { Task { await day.allowLocation() } }`.
  - `spentToday`: header `Spent today`, `day.briefing?.spend.map(SpendRows.init)` or `Nothing spent` in quiet ink.
  - `fromLifo`: header `From LIFO`, `NudgeRows(nudges: day.briefing?.nudges ?? [])`.
  - a tile pair: `HStack(spacing: 12)` of one or two tile buttons, the second slot an empty `Color.clear` frame when nil, so a lone tile keeps half width.
  The `No health data yet` prompt draws before the first tile row whenever `showsHealthPrompt`, as now; tiles keep their ghosting.

- [ ] **Step 3: `TodayScreen` body.** Keep the masthead on top; then on a phone `ForEach(TodayLayout.rows(store.layout.phoneOrder))`, on iPad two `VStack`s (left capped at 520) of `TodayLayout.rows(store.layout.left / .right)`. Host the day model:

```swift
    @State private var day = DayViewModel(date: .now)
    @Environment(\.modelContext) private var context
    @Environment(\.dayProviders) private var providers
    @Environment(\.noteSync) private var sync
    @Environment(\.github) private var github
```

with `.task { attachDay() }`, `.onChange(of: store.layout) { attachDay() }`, the `ModelContext.didSave` debounce reload the day screen uses, `.onChange(of: github?.changeCount) { attachDay() }`, and

```swift
    private func attachDay() {
        day.onlySections = TodayLayout.sections(for: store.layout.phoneOrder)
        day.attach(context, providers: providers, sync: sync)
        day.load()
    }
```

`.onChange(of: github?.state)`: when it becomes `.connected`, `store.offerGitHubOnce()`.

- [ ] **Step 4: RootView** passes `onOpenSettings: { showSettings = true }`.
- [ ] **Step 5:** Build; typography; package suite; commit `feat(today): Today draws the arrangement, with tasks, GitHub, weather, spend and LIFO`.

---

### Task 5: Arranging in place

**Files:** Create `LIfeOS/Features/Today/View/TodayArranging.swift`; Modify `TodayScreen.swift`, `TodayModules.swift`.

- [ ] **Step 1: Enter and leave.** Each module row gets `.onLongPressGesture(minimumDuration: 0.5) { store.isArranging = true }` (only when not arranging) and `.sensoryFeedback(.impact(weight: .light), trigger: store.isArranging)`. The masthead eyebrow reads `Arranging Today` while arranging, with `Button("Done") { store.isArranging = false }` `.editorial(.primary, size: .compact)` beside it. A tap on the canvas background ends arranging; `.onDisappear` ends it (switching tabs).

- [ ] **Step 2: `ArrangeableModule` modifier** (`TodayArranging.swift`), applied to each row while arranging:

```swift
struct ArrangeableModule: ViewModifier {
    let modules: [TodayModule]          // one, or a tile pair
    let isArranging: Bool
    let index: Int
    var onHide: (TodayModule) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var wobble = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isArranging)          // no ticks or opens while arranging
            .overlay(alignment: .topLeading) {
                if isArranging {
                    HStack(spacing: Space.half) {
                        ForEach(modules, id: \.self) { module in
                            Button { onHide(module) } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.plain)
                                .font(LifeOSType.sectionTitle)
                                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                                .accessibilityLabel("Hide \(module.title)")
                        }
                    }
                    .offset(x: -8, y: -8)
                }
            }
            .overlay {
                if isArranging, reduceMotion {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Editorial.quietInk(scheme))
                }
            }
            .rotationEffect(.degrees(isArranging && !reduceMotion ? (wobble ? 1.2 : -1.2) * (index.isMultiple(of: 2) ? 1 : -1) : 0))
            .animation(isArranging && !reduceMotion ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: wobble)
            .onChange(of: isArranging) { _, on in wobble = on }
            .onAppear { wobble = isArranging }
    }
}
```

Drag and drop while arranging: the row (or the first module of a pair) is `.draggable(modules[0].rawValue)`; each row is `.dropDestination(for: String.self) { names, _ in ... }` inserting the dropped module before this row's first module in its column (`store.update { $0.move(dropped, to: column, at: indexOfTarget) }`); each column's trailing spacer (a 44pt `Color.clear` while arranging) is a drop target appending to that column. Tray chips are draggable too.

- [ ] **Step 3: The tray.** While arranging, below the last row: `EditorialSectionHeader(title: "Add to Today")`, a wrapping `HStack` (use the existing flow layout if `DesignSystem` has one; else `ViewThatFits`-free `LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))])`) of `Button("+ \(module.title)") { store.update { $0.add(module) } }` `.editorial(.secondary, size: .compact)`, `.accessibilityLabel("Add \(module.title)")`, `.draggable(module.rawValue)`; GitHub's chip shows only when `github?.state` is connected, else a `Connect GitHub` chip that calls `onOpenSettings`. Then `Button("Reset to default")` `.editorial(.quiet)` behind a `confirmationDialog`.

- [ ] **Step 4: VoiceOver.** Every module row, arranging or not: `.accessibilityAction(named: "Move up") { store.update { $0.moveUp(m) } }`, `Move down`, `Hide`, and on iPad `Move to other column`.

- [ ] **Step 5: The hint.** Under the masthead while `!store.hintSeen && !store.isArranging`: an `.editorialCard()` with `Long-press anything to rearrange Today.` and an `xmark` `.plain` button `Dismiss` setting `hintSeen = true`.

- [ ] **Step 6:** Build; typography; commit `feat(today): arrange Today in place: wobble, hide, drag, a tray to add back`.

---

### Task 6: Previews, UI tests, captures

**Files:** Modify `TodayDesignPreview.swift`, `HealthActivityDesignPreview.swift` (add the three pages to its Today list); Create `LIfeOSUITests/TodayLayoutUITests.swift`.

- [ ] **Step 1: Pages.** `today-custom`: a `TodayLayoutStore(defaults:)` over a throwaway suite (`UserDefaults(suiteName: "preview.today.\(page)")`, cleared first) with layout left `month, tasks, github, nextUp`, right `steps, sleep`, `hintSeen = true`; providers with `StubWeatherProvider`, `StubLocation`, `StubGitHubProvider(state: .card(StubGitHubProvider.sevenCommits, asOf: nil))`; the fixture container (it seeds today's checklist). `today-arranging`: the same with `isArranging = true` and Weather hidden. `today-ipad-custom`: `today-custom` for the iPad simulator. Pass the store into `TodayScreen(layoutStore:)`.

- [ ] **Step 2: UI tests** (add to the `LIfeOSUITests` target with the `xcodeproj` gem, as in the GitHub plan):

```swift
import XCTest

final class TodayLayoutUITests: XCTestCase {
    private func launch(_ page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--page=\(page)"]
        app.launch()
        return app
    }

    func testLongPressHideAndAddBack() {
        let app = launch("today-custom")
        let month = app.otherElements["today.module.month"]
        XCTAssertTrue(month.waitForExistence(timeout: 6))
        month.press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["Arranging Today"].waitForExistence(timeout: 3))
        app.buttons["Hide Month"].tap()
        XCTAssertFalse(app.otherElements["today.module.month"].waitForExistence(timeout: 2))
        let add = app.buttons["Add Month"]
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.otherElements["today.module.month"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["Arranging Today"].exists)
    }

    func testATapWhileArrangingDoesNotTick() {
        let app = launch("today-arranging")
        let row = app.buttons["Draft the plan"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        let before = row.value as? String
        row.tap()
        XCTAssertEqual(row.value as? String, before)
    }
}
```

Give each module row `.accessibilityElement(children: .contain).accessibilityIdentifier("today.module.\(module.rawValue)")` in Task 4/5 so the test can find it; read how `ChecklistRows` exposes a row's ticked state (its accessibility value) before relying on `value`, and assert on whatever it exposes. A drag test (`press(forDuration:thenDragTo:)`) is attempted once; if XCUITest cannot drive SwiftUI's `draggable`, ledger it and rely on the `moveUp` VoiceOver path's package tests.

- [ ] **Step 3: Captures** of the three pages, light and `--dark`, phone and iPad; read them: Month first on `today-custom`, tasks with `3 of 7`, the Project card, tiles two-up; the wobble outline/minus buttons and the tray on `today-arranging`; two columns on iPad.

- [ ] **Step 4:** Run all UI tests; commit `test(today): preview pages and UI tests for arranging Today`.

---

### Task 7: Verification, review, PR

- [ ] Package suite, `swift build`, typography, app build, `AlmanacWidgets` build, all UI tests on the iPhone simulator.
- [ ] Fresh whole-branch review on the most capable model against the spec and this Review Focus; one fix pass with failing tests first.
- [ ] Offer the finishing options (merge, PR, keep); the owner decides whether to push and merge.
