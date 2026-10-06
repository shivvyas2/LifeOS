# Notes Inbox and filing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Notes tab opens on an Inbox with `Inbox | All | To-dos` chips, `New` is one tap into the Inbox with the title focused, the editor's meta row says where a page lives and files it through a picker, cards say what kind they are, Inbox cards swipe to File or Archive, and the drawer's second search field and the old unrouted Inbox screen go.

**Architecture:** The store learns three small things (`isInInbox` on a card, an `inboxCount` on the snapshot, `allCards()` and `moveTargets()` as reads) and `NoteMoveTarget` moves into `Persistence` so the chip, the swipe and the long-press share one list. `NotesHeadline` in `DesignSystem` gains a scope enum of its own. In the app, `NoteSelection` gains `inbox`, `all` and `todos` and loses `recent`; `NotesViewModel` loads cards or task groups by selection and files a shelf-made page; the shelf becomes a `List` on paper so cards carry swipe actions; the editor gains a File chip, a `NoteFilingSheet` and a focus-on-appear; the drawer and the rail drop their search field and get `Inbox` and `All` tiles. The To-dos chip draws the `ChecklistRows` the day screen shipped.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing in `LifeOSKit`, `xcodebuild` and `xcrun simctl` for the simulator checks.

**Spec:** `docs/superpowers/specs/2026-10-06-notes-inbox-editor-walkthrough-design.md`, section 1 plus the focus-on-appear bullet of section 2. PR 1 of the three in section 5.

## Global Constraints

- Paper, ink, hairlines, quiet ink; the accent only for today and anything live; every button `.editorial(role)` or `.plain` around editorial content; fonts only from `LifeOSType` and `Editorial`; no per-module palette. `scripts/check-typography.sh` reports nothing new versus the baseline in Task 0.
- `DesignSystem` has no dependencies and `Persistence` does not know the app's types: the headline takes a `NotesScope` of its own, and `NoteMoveTarget` moves into `Persistence` before `NotesSnapshot` can return it.
- Nothing here changes what Notes syncs, the block model, `NoteIndexer` or the migrations. `NotesStore.createDocument` keeps its tested rule (only a folder files a page); the view model files a shelf-made page with `move`, so the spec's "from a shelf it lands there, filed" holds without touching the store.
- The `LifeOSKit` package also builds for macOS 26: nothing iOS-only in it.
- `LIfeOS/` is a synchronized folder: new files and deletions under it need no `project.pbxproj` edit.
- Commits: conventional `type(scope): imperative summary`, short body, no em dashes, no Claude attribution in commits or the PR body.
- Work happens in `/Users/shivvyas/LIfeOS/.claude/worktrees/notes-inbox` on `feat/notes-inbox`, rebased onto `main` after `feat/day-briefing` merges: the To-dos chip draws that PR's `ChecklistRows` and `ChecklistRow`, and its journal-folder fix keeps today's journal out of the Inbox. `Config/Secrets.xcconfig` is copied in and ignored.
- The simulator for builds and captures is `CalendarAsk iPhone 17`, id `B192EA65-BAA2-4814-A298-94A2F0C8FC87` (iOS 26.2). Peer sessions use the plain `iPhone 17`; do not install on it. Bundle id `com.shivvyas.lifeos`. The plain `sleep` is blocked; wait with `perl -e 'select(undef,undef,undef,4)'`.
- `$OUT` is this session's scratchpad directory; the executor sets it in Task 0.

## Review Focus

1. A card's `isInInbox` must follow filing, or the Inbox shows a page that was filed a moment ago: `NotesStoreTests.aCardSaysWhetherItIsInTheInbox` in Task 1.
2. The Inbox count on the drawer tile must exclude filed and archived pages: `NotesStoreTests.theSnapshotCountsOnlyUnfiledLivePagesAsInbox` in Task 1.
3. The filing picker must list nested folders with their parents, shelves first, or a page cannot be filed where the person keeps it: `NoteSnapshotTests.moveTargetsWalkNestedFoldersShelvesFirst` in Task 1.
4. `All` must be every live page newest first, not the capped list `Recent` was: `NotesStoreTests.allCardsAreEveryLivePageNewestFirst` in Task 1.
5. The eyebrow must never say `1 to-dos` or `0 in Inbox`: `NotesHeadlineTests.scopedWording` in Task 2.

---

## File structure

| File | Responsibility |
|---|---|
| `LifeOSKit/Sources/Persistence/NoteSnapshot.swift` | `NoteCardSnapshot.isInInbox`, `NotesSnapshot.inboxCount`, `NoteMoveTarget`, `NotesSnapshot.moveTargets()` |
| `LifeOSKit/Sources/Persistence/NotesStore.swift` | `allCards()`, the two new snapshot fields filled |
| `LifeOSKit/Tests/PersistenceTests/NoteSnapshotTests.swift` (new) | The move-target walk |
| `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift` | Three new tests |
| `LifeOSKit/Sources/DesignSystem/NotesHeadline.swift` | `NotesScope`, `eyebrow(_:count:)` |
| `LifeOSKit/Tests/DesignSystemTests/NotesHeadlineTests.swift` | Its test |
| `LIfeOS/Features/Notes/Model/NoteSelection.swift` | `inbox`, `all`, `todos`; `streamChip`; `init(chip:)` |
| `LIfeOS/Features/Notes/Model/NoteTaskGroup.swift` (new) | A page and its open to-dos as rows; `NoteEditorFocus` |
| `LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift` | Selection default, loading by selection, task groups, scope, titles, filing on create, `toggleTask`, `moveTargets` |
| `LIfeOS/Features/Notes/Model/NotesCommands.swift` | `selectInbox` on Command-Option-0 |
| `LIfeOS/Features/Notes/View/NotesLibraryList.swift`, `NotesSidebar.swift` | No search field; `Inbox`, `All`, `Favourites`, `Habits` |
| `LIfeOS/Features/Notes/View/NotesHubScreen.swift` | Routes carry a focus; `open(_:focus:)`; the shelf's new callbacks; `NoteEditorHost(focus:)` |
| `LIfeOS/Features/Notes/View/NoteShelfScreen.swift` | Rewritten: the `List`, the chips, `New`, swipe actions, the To-dos groups, the filing sheet |
| `LIfeOS/Features/Notes/View/NoteFilingSheet.swift` (new) | The picker with nested folders and `New folder` |
| `LIfeOS/Features/Notes/View/NoteCard.swift` | Kind eyebrow and `Inbox` caption; `NoteMoveTarget` removed |
| `LIfeOS/Features/Notes/View/NoteEditorScreen.swift` | The File chip, the sheet, focus on appear |
| `LIfeOS/Features/Notes/ViewModel/NoteEditorViewModel.swift` | `folderID`, `folderName`, `isInInbox`, `file(to:folderID:)`, `createFolder`, `moveTargets()` |
| `LIfeOS/Features/Notes/View/NoteInboxScreen.swift`, `LIfeOS/Features/Notes/ViewModel/NoteInboxViewModel.swift` (deleted) | |
| `LIfeOS/Features/Today/View/TodayDesignPreview.swift`, `LIfeOS/Features/Notes/View/NotesDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift` | Pages `notes` (`--scope=`), `notes-empty`, `notes-editor-new`, `notes-filing` |

---

### Task 0: Rebase, worktree and baselines

Do not start until `feat/day-briefing` is on `main`.

- [ ] **Step 1: Rebase onto main and confirm the day screen's pieces are here**

```bash
cd /Users/shivvyas/LIfeOS/.claude/worktrees/notes-inbox
git fetch origin && git merge-base --is-ancestor origin/feat/day-briefing origin/main && echo "day briefing is on main" || echo "STOP: day briefing not merged"
git rebase origin/main && git log --oneline -3
ls LifeOSKit/Sources/Persistence/DayChecklist.swift LIfeOS/Features/Day/View/DaySections.swift
grep -n "journalFolderID" LifeOSKit/Sources/Persistence/NotesStore.swift | head -2
ls Config/Secrets.xcconfig || cp /Users/shivvyas/LIfeOS/Config/Secrets.xcconfig Config/Secrets.xcconfig
git check-ignore -q Config/Secrets.xcconfig && echo "secrets ignored"
```

Expected: `day briefing is on main`, a clean rebase with the spec commit on top, both files present, `journalFolderID` found, the secrets file ignored.

- [ ] **Step 2: Baselines**

```bash
OUT=/private/tmp/claude-501/-Users-shivvyas-LIfeOS/$(ls /private/tmp/claude-501/-Users-shivvyas-LIfeOS | head -1)/scratchpad; echo "OUT=$OUT"
(cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*Test run with" | tail -1)
scripts/check-typography.sh > $OUT/typo-notes-base.txt 2>&1; echo "typography baseline lines: $(wc -l < $OUT/typo-notes-base.txt)"
xcrun simctl list devices | grep "CalendarAsk" || xcrun simctl create "CalendarAsk iPhone 17" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
df -h / | tail -1
```

- [ ] **Step 3: Commit the plan**

```bash
git add docs/superpowers/plans/2026-10-06-notes-inbox.md
git commit -m "docs(plans): the Notes Inbox and filing"
```

---

### Task 1: The store knows the Inbox

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteSnapshot.swift`, `LifeOSKit/Sources/Persistence/NotesStore.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/NoteSnapshotTests.swift` (new), `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift`

**Interfaces:**
- Produces: `NoteCardSnapshot.isInInbox: Bool` (init parameter, defaulted `false`); `NotesSnapshot.inboxCount: Int` (init parameter, defaulted 0); `public struct NoteMoveTarget: Identifiable, Hashable, Sendable { bucket; folderID; title; depth: Int; isCurrentHome(of:) }`; `NotesSnapshot.moveTargets() -> [NoteMoveTarget]`; `NotesStore.allCards() throws -> [NoteCardSnapshot]`. Tasks 3 to 5 consume them.

- [ ] **Step 1: Write the failing tests**

`NoteSnapshotTests.swift`:

```swift
import Testing
import Foundation
@testable import Persistence

@Suite struct NoteSnapshotTests {
    private func folder(_ name: String, bucket: NoteBucket, children: [NoteFolderSnapshot] = []) -> NoteFolderSnapshot {
        NoteFolderSnapshot(id: UUID(), name: name, icon: "", accent: .sage, bucket: bucket, parentID: nil, count: 0, children: children)
    }

    @Test func moveTargetsWalkNestedFoldersShelvesFirst() {
        let drills = folder("Drills", bucket: .projects)
        let training = folder("Training", bucket: .projects, children: [drills])
        let snapshot = NotesSnapshot(folders: [.projects: [training], .areas: [folder("Home", bucket: .areas)]])

        let targets = snapshot.moveTargets()

        #expect(targets.map(\.title) == ["Projects", "Training", "Training / Drills", "Areas", "Home", "Research"])
        #expect(targets.map(\.depth) == [0, 1, 2, 0, 1, 0])
        #expect(targets[2].folderID == drills.id && targets[2].bucket == .projects)
        #expect(targets[0].folderID == nil)
        #expect(!targets.contains { $0.bucket == .archive })
    }
}
```

Append to `NotesStoreTests.swift`, inside the suite:

```swift
    @Test func aCardSaysWhetherItIsInTheInbox() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Idea", bucket: .projects)
        #expect(try store.inbox().first?.isInInbox == true)

        try store.move(document, to: .areas, folderID: nil)

        #expect(try store.cards(bucket: .areas).first?.isInInbox == false)
    }

    @Test func theSnapshotCountsOnlyUnfiledLivePagesAsInbox() throws {
        let store = try makeStore()
        _ = try store.createDocument(title: "Loose", bucket: .projects)
        let filed = try store.createDocument(title: "Filed", bucket: .projects)
        try store.move(filed, to: .projects, folderID: nil)
        let archived = try store.createDocument(title: "Archived", bucket: .projects)
        try store.archive(archived)

        #expect(try store.snapshot().inboxCount == 1)
    }

    @Test func allCardsAreEveryLivePageNewestFirst() throws {
        let store = try makeStore()
        let first = try store.createDocument(title: "First", bucket: .projects)
        let second = try store.createDocument(title: "Second", bucket: .areas)
        let archived = try store.createDocument(title: "Gone", bucket: .research)
        try store.archive(archived)
        try store.rename(second, to: "Second again")

        let all = try store.allCards()
        #expect(all.map(\.id) == [second.id, first.id])
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd LifeOSKit && swift test --filter "NoteSnapshotTests|NotesStoreTests"`
Expected: compile errors, `value of type 'NotesSnapshot' has no member 'moveTargets'`, `no member 'isInInbox'`, `no member 'inboxCount'`, `no member 'allCards'`.

- [ ] **Step 3: Change the snapshot and the store**

In `NoteSnapshot.swift`:

(a) In `NoteCardSnapshot`, after `public let linkCount: Int`, add:

```swift
    /// Unfiled and not archived: the page is still waiting to be put away.
    public let isInInbox: Bool
```

and in its init add the parameter `isInInbox: Bool = false` after `openedAt: Date? = nil` and the assignment `self.isInInbox = isInInbox` after `self.linkCount = linkCount`.

(b) In `NotesSnapshot`, after `public let totalCount: Int`, add `public let inboxCount: Int`; add the init parameter `inboxCount: Int = 0` after `totalCount: Int = 0` and the assignment `self.inboxCount = inboxCount`. After `count(in:)`, add:

```swift
    /// Everywhere a page can be filed: each shelf in `NoteBucket.filing`
    /// first, then its folders in tree order, each child named after its
    /// parent. One list, so the editor's chip, a swipe and a long-press
    /// cannot offer different places.
    public func moveTargets() -> [NoteMoveTarget] {
        var targets: [NoteMoveTarget] = []
        for bucket in NoteBucket.filing {
            targets.append(NoteMoveTarget(bucket: bucket, folderID: nil, title: bucket.title, depth: 0))
            func walk(_ folders: [NoteFolderSnapshot], prefix: String, depth: Int) {
                for folder in folders {
                    let name = prefix.isEmpty ? folder.name : "\(prefix) / \(folder.name)"
                    targets.append(NoteMoveTarget(bucket: bucket, folderID: folder.id, title: name, depth: depth))
                    walk(folder.children, prefix: name, depth: depth + 1)
                }
            }
            walk(folders(in: bucket), prefix: "", depth: 1)
        }
        return targets
    }
```

(c) At the end of the file add:

```swift
/// Somewhere a page can be filed: a shelf, or a folder on one.
public struct NoteMoveTarget: Identifiable, Hashable, Sendable {
    public let bucket: NoteBucket
    /// Nil for the shelf itself, which files the page loose on it.
    public let folderID: UUID?
    /// `Training / Drills` for a nested folder; the shelf's own name at the root.
    public let title: String
    /// 0 for the shelf, 1 for its folders, 2 for theirs.
    public let depth: Int

    public init(bucket: NoteBucket, folderID: UUID?, title: String, depth: Int = 0) {
        self.bucket = bucket; self.folderID = folderID; self.title = title; self.depth = depth
    }

    public var id: String { "\(bucket.rawValue)-\(folderID?.uuidString ?? "root")" }

    /// The last part of the title, for a row that shows its depth by indent.
    public var leafName: String {
        title.components(separatedBy: " / ").last ?? title
    }

    /// Greys out the place the page already is.
    public func isCurrentHome(of card: NoteCardSnapshot) -> Bool {
        card.bucket == bucket && card.folderID == folderID
    }

    public func isCurrentHome(bucket: NoteBucket, folderID: UUID?) -> Bool {
        self.bucket == bucket && self.folderID == folderID
    }
}
```

In `NotesStore.swift`:

(d) In `snapshot()`, change the return to include the count:

```swift
        return NotesSnapshot(
            folders: tree,
            counts: counts,
            recent: try recent(),
            favorites: try favorites(),
            totalCount: allDocuments.filter { !$0.isArchived }.count,
            inboxCount: allDocuments.filter(\.isInInbox).count
        )
```

(e) After `inbox()`, add:

```swift
    /// Every live page, newest edit first: the All chip.
    public func allCards() throws -> [NoteCardSnapshot] {
        try cardsNewestFirst()
    }
```

(f) In `card(_:folderNames:)`, add `isInInbox: document.isInInbox` after `openedAt: document.openedAt`.

- [ ] **Step 4: Run the Persistence suites**

Run: `cd LifeOSKit && swift test --filter "NoteSnapshotTests|NotesStoreTests|NoteStreamTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteSnapshot.swift LifeOSKit/Sources/Persistence/NotesStore.swift \
  LifeOSKit/Tests/PersistenceTests/NoteSnapshotTests.swift LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift
git commit -m "feat(persistence): cards say when they are in the Inbox, and one list of places to file

NoteMoveTarget moves into the package with the snapshot's moveTargets()
walk, the snapshot counts the Inbox, and allCards() is the All chip."
```

---

### Task 2: The eyebrow by scope

**Files:**
- Modify: `LifeOSKit/Sources/DesignSystem/NotesHeadline.swift`
- Test: `LifeOSKit/Tests/DesignSystemTests/NotesHeadlineTests.swift`

**Interfaces:**
- Produces: `public enum NotesScope: Sendable { inbox, all, todos, favorites, pages }` and `NotesHeadline.eyebrow(_ scope: NotesScope, count: Int) -> String`; `eyebrow(count:)` stays. Task 3 maps the selection to a scope.

- [ ] **Step 1: Write the failing test**

Replace the test file with:

```swift
import Testing
@testable import DesignSystem

@Suite struct NotesHeadlineTests {
    @Test func countWording() {
        #expect(NotesHeadline.eyebrow(count: 0) == "Notes · No pages")
        #expect(NotesHeadline.eyebrow(count: 1) == "Notes · 1 page")
        #expect(NotesHeadline.eyebrow(count: 24) == "Notes · 24 pages")
    }

    @Test func scopedWording() {
        #expect(NotesHeadline.eyebrow(.inbox, count: 0) == "Notes · Nothing in Inbox")
        #expect(NotesHeadline.eyebrow(.inbox, count: 1) == "Notes · 1 in Inbox")
        #expect(NotesHeadline.eyebrow(.inbox, count: 3) == "Notes · 3 in Inbox")
        #expect(NotesHeadline.eyebrow(.all, count: 24) == "Notes · 24 pages")
        #expect(NotesHeadline.eyebrow(.pages, count: 1) == "Notes · 1 page")
        #expect(NotesHeadline.eyebrow(.todos, count: 0) == "Notes · No to-dos")
        #expect(NotesHeadline.eyebrow(.todos, count: 1) == "Notes · 1 to-do")
        #expect(NotesHeadline.eyebrow(.todos, count: 5) == "Notes · 5 to-dos")
        #expect(NotesHeadline.eyebrow(.favorites, count: 0) == "Notes · No favourites")
        #expect(NotesHeadline.eyebrow(.favorites, count: 1) == "Notes · 1 favourite")
        #expect(NotesHeadline.eyebrow(.favorites, count: 2) == "Notes · 2 favourites")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd LifeOSKit && swift test --filter NotesHeadlineTests`
Expected: compile error, `cannot infer contextual base in reference to member 'inbox'`.

- [ ] **Step 3: Write the value**

Replace `NotesHeadline.swift` with:

```swift
/// What the Notes shelf is showing, as far as the eyebrow cares.
public enum NotesScope: Sendable {
    case inbox, all, todos, favorites, pages
}

/// The Notes masthead eyebrow, so "1 pages" never ships.
public enum NotesHeadline {
    public static func eyebrow(count: Int) -> String {
        switch count {
        case 0: "Notes · No pages"
        case 1: "Notes · 1 page"
        default: "Notes · \(count) pages"
        }
    }

    public static func eyebrow(_ scope: NotesScope, count: Int) -> String {
        switch scope {
        case .inbox:
            count == 0 ? "Notes · Nothing in Inbox" : "Notes · \(count) in Inbox"
        case .all, .pages:
            eyebrow(count: count)
        case .todos:
            switch count {
            case 0: "Notes · No to-dos"
            case 1: "Notes · 1 to-do"
            default: "Notes · \(count) to-dos"
            }
        case .favorites:
            switch count {
            case 0: "Notes · No favourites"
            case 1: "Notes · 1 favourite"
            default: "Notes · \(count) favourites"
            }
        }
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `cd LifeOSKit && swift test --filter NotesHeadlineTests`
Expected: `2 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/DesignSystem/NotesHeadline.swift LifeOSKit/Tests/DesignSystemTests/NotesHeadlineTests.swift
git commit -m "feat(design): the Notes eyebrow by scope, as a tested value"
```

---

### Task 3: The selection, the view model, the commands, the library

**Files:**
- Modify: `LIfeOS/Features/Notes/Model/NoteSelection.swift`, `LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift`, `LIfeOS/Features/Notes/Model/NotesCommands.swift`, `LIfeOS/Features/Notes/View/NotesLibraryList.swift`, `LIfeOS/Features/Notes/View/NotesSidebar.swift`, `LIfeOS/Features/Notes/View/NotesHubScreen.swift`
- Create: `LIfeOS/Features/Notes/Model/NoteTaskGroup.swift`

**Interfaces:**
- Consumes: Task 1 and 2; `ChecklistRow` from `Persistence` (the day screen PR).
- Produces: `NoteSelection { inbox, all, todos, favorites, bucket, folder; var streamChip: NoteStreamChip?; init(chip:) }`; `struct NoteTaskGroup: Identifiable { page: NoteCardSnapshot; rows: [ChecklistRow] }`; `enum NoteEditorFocus: Hashable { none, title, firstBlock }`; on `NotesViewModel`: `selection` defaults to `.inbox`, `private(set) var tasks: [NoteTaskGroup]`, `var scope: NotesScope`, `var headerCount: Int`, `var isStream: Bool`, `func toggleTask(documentID:blockID:)`, `func moveTargets() -> [NoteMoveTarget]`, `func makeFolder(named:in:) -> UUID?`, `createNote` files a shelf-made page; `NotesCommandTarget.selectInbox`; `NotesLibraryList` and `NotesSidebar` without `query:` and `isSearchFocused:`; `NotesHubScreen.open(_:focus:)`, `NoteRoute.page(UUID, focus: NoteEditorFocus)`, `NoteEditorHost(documentID:focus:onOpenLinked:)`, the shelf called with `onOpenNew:` and without `onNewFolder:`.

The view models live in the app target, which has no test target; this task's gate is the build and Task 6's previews.

- [ ] **Step 1: The selection and the new model file**

In `NoteSelection.swift`, replace the `NoteSelection` enum (lines 4 to 24) with:

```swift
/// What the library currently points at.
///
/// One enum rather than a pair of optionals, because "a folder is selected"
/// and "a shelf is selected" are mutually exclusive and expressing them as
/// two nullable properties makes a fourth, meaningless state representable.
/// The first three are the stream chips across the top of the shelf.
enum NoteSelection: Hashable {
    case inbox
    case all
    case todos
    case favorites
    case bucket(NoteBucket)
    case folder(UUID)

    var bucket: NoteBucket? {
        if case .bucket(let bucket) = self { return bucket }
        return nil
    }

    var folderID: UUID? {
        if case .folder(let id) = self { return id }
        return nil
    }

    /// The chip this selection is, or nil on a shelf, a folder or favourites.
    var streamChip: NoteStreamChip? {
        switch self {
        case .inbox: .inbox
        case .all: .all
        case .todos: .todos
        default: nil
        }
    }

    init(chip: NoteStreamChip) {
        switch chip {
        case .inbox: self = .inbox
        case .all: self = .all
        case .todos: self = .todos
        }
    }
}
```

Create `NoteTaskGroup.swift`:

```swift
import Foundation
import Persistence

/// One page's open to-dos, as the rows the day screen draws, under the
/// page's title. What the To-dos chip lists.
struct NoteTaskGroup: Identifiable, Equatable {
    let page: NoteCardSnapshot
    let rows: [ChecklistRow]
    var id: UUID { page.id }
}

/// What the editor focuses when a page opens: nothing for a page being
/// read, the title for one `New` just made, the first block when the
/// walkthrough wants the block picker up.
enum NoteEditorFocus: Hashable {
    case none, title, firstBlock
}
```

- [ ] **Step 2: The view model**

In `NotesViewModel.swift`:

(a) Add `import DesignSystem` after `import Persistence`.

(b) Replace `private(set) var cards: [NoteCardSnapshot] = []` and the `selection` declaration with:

```swift
    private(set) var cards: [NoteCardSnapshot] = []
    /// The To-dos chip's rows, grouped by page. Empty on every other selection.
    private(set) var tasks: [NoteTaskGroup] = []

    var selection: NoteSelection = .inbox {
        didSet { if selection != oldValue { load() } }
    }
```

(c) Replace the `switch selection { ... }` and `cards = sorted(cards)` in `load()` (lines 66 to 77) with:

```swift
            tasks = []
            switch selection {
            case .inbox:
                cards = try store.inbox()
            case .all:
                cards = try store.allCards()
            case .todos:
                cards = []
                tasks = try taskGroups(store)
                return
            case .favorites:
                cards = try store.favorites()
            case .bucket(let bucket):
                cards = try store.cards(bucket: bucket, kind: filter.kind)
            case .folder(let id):
                let bucket = try store.folder(id: id)?.bucket ?? .projects
                cards = try store.cards(bucket: bucket, folder: .some(id), kind: filter.kind)
            }
            cards = sorted(cards)
```

(d) After `sorted(_:)`, add:

```swift
    /// The open to-dos of every live page, in the index's order (newest page
    /// first, written order within a page), each page's rows under its
    /// title. A second read for the titles; the index carries only ids.
    private func taskGroups(_ store: NotesStore) throws -> [NoteTaskGroup] {
        guard case .tasks(let rows) = try store.stream(for: .todos) else { return [] }
        let pages = Dictionary(uniqueKeysWithValues: try store.allCards().map { ($0.id, $0) })
        var order: [UUID] = []
        var byPage: [UUID: [ChecklistRow]] = [:]
        for task in rows {
            guard pages[task.documentID] != nil else { continue }
            if byPage[task.documentID] == nil { order.append(task.documentID) }
            byPage[task.documentID, default: []].append(ChecklistRow(
                source: .page(documentID: task.documentID, blockID: task.id),
                text: task.text, detail: nil, isDone: task.isChecked, isEditable: true
            ))
        }
        return order.compactMap { id in pages[id].map { NoteTaskGroup(page: $0, rows: byPage[id] ?? []) } }
    }
```

(e) Replace the `// MARK: - Header` block's `activeBucket` doc comment and the `headerTitle`, `headerBlurb` and `breadcrumb` switches so every case is covered:

```swift
    /// The shelf a new page lands on, given where the library points. The
    /// stream chips and Favourites are views, not places, so a page made from
    /// them goes to Projects, which is where PARA says active work goes, and
    /// stays in the Inbox until it is filed.
    var activeBucket: NoteBucket {
        switch selection {
        case .bucket(let bucket): bucket == .archive ? .projects : bucket
        case .folder(let id):     (try? store?.folder(id: id))??.bucket ?? .projects
        default:                  .projects
        }
    }

    var activeFolderID: UUID? { selection.folderID }

    /// The chips are shown on the three stream selections only.
    var isStream: Bool { selection.streamChip != nil }

    var scope: NotesScope {
        switch selection {
        case .inbox: .inbox
        case .all: .all
        case .todos: .todos
        case .favorites: .favorites
        case .bucket, .folder: .pages
        }
    }

    /// What the eyebrow counts: rows on the To-dos chip, cards everywhere else.
    var headerCount: Int {
        selection == .todos ? tasks.reduce(0) { $0 + $1.rows.count } : cards.count
    }

    var headerTitle: String {
        if isSearching { return "Search" }
        switch selection {
        case .inbox:               return "Inbox"
        case .all:                 return "All pages"
        case .todos:               return "To-dos"
        case .favorites:           return "Favourites"
        case .bucket(let bucket):  return bucket.title
        case .folder(let id):      return folderSnapshot(id)?.name ?? "Folder"
        }
    }

    var headerBlurb: String {
        if isSearching {
            return cards.isEmpty
                ? "Nothing matches \"\(query)\" yet."
                : "\(cards.count) \(cards.count == 1 ? "page" : "pages") matching \"\(query)\"."
        }
        switch selection {
        case .inbox:
            return "Pages you have not put away yet. File one from its editor, or swipe it."
        case .all:
            return "Every page, newest first. Nothing is filed here; this is a view onto everything else."
        case .todos:
            return "Every open to-do from every page, in one list."
        case .favorites:
            return "Pages you starred, from every shelf."
        case .bucket(let bucket):
            return bucket.blurb
        case .folder(let id):
            guard let folder = folderSnapshot(id) else { return "" }
            return "\(folder.count) \(folder.count == 1 ? "page" : "pages") in \(folder.name), filed under \(folder.bucket.title)."
        }
    }

    var headerAccent: NoteAccent {
        switch selection {
        case .folder(let id): folderSnapshot(id)?.accent ?? .sage
        case .bucket(let bucket): NoteAccent.derived(from: bucket.rawValue)
        default: .slate
        }
    }

    /// "Library / Projects / Training", the trail across the top of the shelf.
    var breadcrumb: [String] {
        var trail = ["Library"]
        switch selection {
        case .inbox:     trail.append("Inbox")
        case .all:       trail.append("All pages")
        case .todos:     trail.append("To-dos")
        case .favorites: trail.append("Favourites")
        case .bucket(let bucket): trail.append(bucket.title)
        case .folder(let id):
            if let folder = folderSnapshot(id) {
                trail.append(folder.bucket.title)
                trail.append(folder.name)
            }
        }
        return trail
    }

    /// Everywhere a page can be filed, from the current snapshot.
    func moveTargets() -> [NoteMoveTarget] { snapshot.moveTargets() }

    /// A folder made from the filing sheet: created and answered, the
    /// selection left where it was. `createFolder(named:in:icon:)` selects
    /// what it makes, which is right for the library and wrong here.
    func makeFolder(named name: String, in bucket: NoteBucket) -> UUID? {
        guard let store else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let folder = try? store.createFolder(name: trimmed, bucket: bucket) else { return nil }
        load()
        requestSync()
        return folder.id
    }
```

(f) Replace `createNote(kind:title:)` with:

```swift
    /// Creates a page and returns its id, so the caller can open it straight
    /// into the editor. From a shelf the page is filed loose on that shelf
    /// (choosing a shelf is choosing a home); from a folder it is filed in it;
    /// from the Inbox, All, To-dos or Favourites it stays in the Inbox.
    @discardableResult
    func createNote(kind: NoteKind = .note, title: String = "") -> UUID? {
        guard let store else { return nil }
        do {
            let document = try store.createDocument(
                title: title,
                kind: kind,
                bucket: activeBucket,
                folderID: activeFolderID
            )
            if case .bucket(let bucket) = selection, bucket != .archive {
                try store.move(document, to: bucket, folderID: nil)
            }
            load()
            requestSync()
            return document.id
        } catch {
            assertionFailure("Note create failed: \(error)")
            return nil
        }
    }
```

(g) After `move(_:to:folderID:)`, add:

```swift
    /// Ticks a to-do on the To-dos chip, through the same path the editor
    /// takes, so the index and the page agree.
    func toggleTask(documentID: UUID, blockID: UUID) {
        mutate(documentID) { store, document in
            let result = NoteBlockEditor.toggleCheck(document.blocks, at: blockID)
            guard result.handled else { return }
            try store.update(document, blocks: result.blocks)
        }
    }
```

- [ ] **Step 3: The commands**

In `NotesCommands.swift`: rename `let selectRecent: () -> Void` to `let selectInbox: () -> Void` (line 22), and change the menu item (lines 72 to 77) to:

```swift
            // Command-Option-number, matching how browsers and editors number
            // their tabs, with the Inbox at zero because it is the one that is
            // not a shelf.
            Button("Inbox") { target?.selectInbox() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(target == nil)
```

- [ ] **Step 4: The drawer**

In `NotesLibraryList.swift`:

(a) Delete `@Binding var query: String` (line 20), `var isSearchFocused: Binding<Bool>?` (21), `@FocusState private var searchFieldFocused: Bool` (34), the `searchField` line in the body (45), the two `.onChange` modifiers (57 to 62), and the whole `// MARK: - Search` section with `searchField` (65 to 92).

(b) Replace `shortcuts` (lines 96 to 111) with:

```swift
    /// Inbox, All, Favourites and Habits as four tiles in two rows: the
    /// things reached for most, reachable without scrolling past the shelves.
    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            shortcutTile(.inbox, title: "Inbox", systemImage: "tray.fill",
                         count: snapshot.inboxCount)
            shortcutTile(.all, title: "All", systemImage: "doc.on.doc.fill",
                         count: snapshot.totalCount)
            shortcutTile(.favorites, title: "Favourites", systemImage: "star.fill",
                         count: snapshot.favorites.count)
            Button(action: onOpenHabits) {
                tileLabel(title: "Habits", systemImage: "flame.fill",
                          count: habitCount, isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens habits")
        }
    }
```

- [ ] **Step 5: The rail**

In `NotesSidebar.swift`:

(a) Delete `@Binding var query: String` (14), the `isSearchFocused` doc comment and property (15 to 18), `@FocusState private var searchFieldFocused: Bool` (38), the `searchField` lines in the body (46 to 48), and the `searchField` property (67 to 95).

(b) Replace the two `shortcut(...)` calls in the body (lines 50 to 53) with:

```swift
                shortcut(.inbox, title: "Inbox", systemImage: "tray.fill",
                         hue: .recovery, count: snapshot.inboxCount)
                shortcut(.all, title: "All", systemImage: "doc.on.doc.fill",
                         hue: .recovery, count: snapshot.totalCount)
                shortcut(.favorites, title: "Favourites", systemImage: "star.fill",
                         hue: .activity, count: snapshot.favorites.count)
```

- [ ] **Step 6: The hub**

In `NotesHubScreen.swift`:

(a) `NoteRoute` becomes:

```swift
    enum NoteRoute: Hashable {
        case page(UUID, focus: NoteEditorFocus)
        case habits
    }
```

(b) Add `@State private var openPageFocus: NoteEditorFocus = .none` after `@State private var openPage: UUID?`.

(c) In `.onChange(of: isThreeColumn)`: `if case .page(let id) = path.last` becomes `if case .page(let id, let focus) = path.last` with `openPageFocus = focus` added before `openPage = id`; and `path.append(.page(page))` becomes `path.append(.page(page, focus: openPageFocus))`.

(d) `detailColumn`'s host becomes `NoteEditorHost(documentID: openPage, focus: openPageFocus, onOpenLinked: { open($0) })`.

(e) `library` and `libraryList` lose their `query:` lines, and `libraryList` loses `isSearchFocused: $isSearchFocused,`.

(f) `destination(_:)`'s page case becomes:

```swift
        case .page(let id, let focus):
            NoteEditorHost(documentID: id, focus: focus, onOpenLinked: { open($0) })
```

(g) `shelf` becomes:

```swift
    private var shelf: some View {
        NoteShelfScreen(
            model: model,
            openPageID: openPage,
            onOpen: { open($0) },
            onOpenNew: { open($0, focus: .title) },
            // Offered only where there is a library to collapse.
            onToggleLibrary: layout.isRegular ? { isLibraryVisible.toggle() } : nil,
            isLibraryVisible: isLibraryVisible,
            isSearchFocused: $isSearchFocused
        )
        .navigationBarTitleDisplayMode(.inline)
        .shellToolbar()
    }
```

(h) In `commandTarget`: `newPage: { if let id = model.createNote() { open(id, focus: .title) } }`, and `selectRecent: { model.selection = .recent ... }` becomes `selectInbox: { model.selection = .inbox; path.removeAll(); openPage = nil }`.

(i) `open(_:)` becomes:

```swift
    /// Opens a page wherever this arrangement puts one, focusing what the
    /// caller asked for: the title for a page just made, nothing otherwise.
    private func open(_ id: UUID, focus: NoteEditorFocus = .none) {
        if isThreeColumn {
            openPageFocus = focus
            openPage = id
        } else {
            path.append(.page(id, focus: focus))
        }
    }
```

(j) `NoteEditorHost` loses `private` and gains the focus:

```swift
/// Builds an editor view model for one page and keeps it alive for as long as
/// the page is on screen.
///
/// A separate view because the model has to be created with the document id in
/// hand, and `@State` cannot be initialised from a navigation destination's
/// argument without a wrapper like this one.
struct NoteEditorHost: View {
    let documentID: UUID
    var focus: NoteEditorFocus = .none
    var onOpenLinked: (UUID) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.noteSync) private var sync
    @State private var model: NoteEditorViewModel?

    var body: some View {
        Group {
            if let model, model.documentID == documentID {
                NoteEditorScreen(model: model, focusOnAppear: focus, onOpenLinked: onOpenLinked)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: documentID) {
            let editor = NoteEditorViewModel(documentID: documentID)
            editor.attach(context, sync: sync)
            editor.load()
            model = editor
        }
    }
}
```

`NoteEditorScreen(model:focusOnAppear:onOpenLinked:)` lands in Task 5; until then this file does not compile, so Task 3 ends with the Task 4 shelf and the Task 5 editor still to come. Build at the end of Task 5; commit this task's files now, since each task's diff should read on its own.

- [ ] **Step 7: Commit**

```bash
git add LIfeOS/Features/Notes/Model/NoteSelection.swift LIfeOS/Features/Notes/Model/NoteTaskGroup.swift \
  LIfeOS/Features/Notes/ViewModel/NotesViewModel.swift LIfeOS/Features/Notes/Model/NotesCommands.swift \
  LIfeOS/Features/Notes/View/NotesLibraryList.swift LIfeOS/Features/Notes/View/NotesSidebar.swift LIfeOS/Features/Notes/View/NotesHubScreen.swift
git commit -m "feat(notes): the Inbox, All and To-dos selections, and pages that open with a focus

The view model loads cards or task groups by selection, files a page
made on a shelf, and ticks a to-do from the chip; the library drawer and
rail lose their second search field and gain Inbox and All; routes
carry what the editor should focus."
```

---

### Task 4: The shelf, the cards and the filing sheet

**Files:**
- Rewrite: `LIfeOS/Features/Notes/View/NoteShelfScreen.swift`
- Create: `LIfeOS/Features/Notes/View/NoteFilingSheet.swift`
- Modify: `LIfeOS/Features/Notes/View/NoteCard.swift`
- Delete: `LIfeOS/Features/Notes/View/NoteInboxScreen.swift`, `LIfeOS/Features/Notes/ViewModel/NoteInboxViewModel.swift`

**Interfaces:**
- Consumes: Task 3's view model, `UnderlinePicker`, `HairlineField`, `EditorialEmptyState`, `ChecklistRows(rows:onTick:onOpen:)` from the day screen PR, `NoteMoveTarget`.
- Produces: `NoteShelfScreen(model:openPageID:onOpen:onOpenNew:onToggleLibrary:isLibraryVisible:isSearchFocused:)`; `NoteFilingSheet(targets:currentBucket:currentFolderID:onPick:onCreateFolder:)`, which Task 5 reuses.

- [ ] **Step 1: The filing sheet**

```swift
import SwiftUI
import DesignSystem
import Persistence

/// Where a page goes: each shelf first, then its folders with their depth as
/// an indent, and a way to make a folder without leaving. The one picker
/// behind the editor's chip and the Inbox swipe.
struct NoteFilingSheet: View {
    let targets: [NoteMoveTarget]
    var currentBucket: NoteBucket?
    var currentFolderID: UUID?
    var onPick: (NoteMoveTarget) -> Void
    /// Makes a folder and answers its id, or nil when it could not.
    var onCreateFolder: (String, NoteBucket) -> UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var newName = ""
    @State private var newBucket: NoteBucket = .projects

    var body: some View {
        NavigationStack {
            List {
                ForEach(NoteBucket.filing) { bucket in
                    Section {
                        ForEach(targets.filter { $0.bucket == bucket }) { target in
                            Button {
                                onPick(target)
                                dismiss()
                            } label: {
                                HStack(spacing: Space.x1) {
                                    Image(systemName: target.folderID == nil ? "tray" : "folder")
                                        .foregroundStyle(Editorial.quietInk(scheme))
                                    Text(target.folderID == nil ? "On \(bucket.title)" : target.leafName)
                                        .font(LifeOSType.secondary)
                                }
                                .padding(.leading, CGFloat(max(0, target.depth - 1)) * Space.x2)
                            }
                            .disabled(target.isCurrentHome(bucket: currentBucket ?? .projects, folderID: currentFolderID)
                                      && currentBucket != nil)
                        }
                    } header: {
                        Text(bucket.title).editorialEyebrow()
                    }
                }
                Section {
                    HairlineField(text: $newName, placeholder: "New folder name", glyph: "folder.badge.plus",
                                  submitLabel: .done, onSubmit: createAndFile)
                    Picker("Shelf", selection: $newBucket) {
                        ForEach(NoteBucket.filing) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Create and file here", action: createAndFile)
                        .buttonStyle(.editorial(.primary, size: .compact))
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("New folder").editorialEyebrow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LifeOSTokens.canvas.resolve(scheme))
            .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            .navigationTitle("File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createAndFile() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = onCreateFolder(name, newBucket) else { return }
        onPick(NoteMoveTarget(bucket: newBucket, folderID: id, title: name, depth: 1))
        dismiss()
    }
}
```

- [ ] **Step 2: The cards**

In `NoteCard.swift`:

(a) Replace the caption line `Text(card.folderName ?? card.bucket.title).lineLimit(1)` (line 47) with:

```swift
                        if card.kind != .note {
                            Text(card.kind == .journal ? "Journal" : "Tasks").editorialEyebrow()
                        }
                        Text(card.folderName ?? (card.isInInbox ? "Inbox" : card.bucket.title)).lineLimit(1)
```

(b) Delete the `NoteMoveTarget` struct at the end of the file (lines 166 to 180, with its doc comment); the package's replaces it, and `target.isCurrentHome(of: card)` keeps compiling.

- [ ] **Step 3: The shelf**

Replace `NoteShelfScreen.swift` in full:

```swift
import SwiftUI
import DesignSystem
import Persistence

/// The page library, shared by iPhone and iPad columns: the Inbox, All or
/// To-dos stream, or one shelf or folder, over the same search.
///
/// A `List` on paper rather than a scroll view, so a card can carry swipe
/// actions; everything that is not a card is a row too, with the list's
/// own chrome switched off.
struct NoteShelfScreen: View {
    @Bindable var model: NotesViewModel
    var openPageID: UUID?
    var onOpen: (UUID) -> Void
    /// A page `New` just made: opened with its title focused.
    var onOpenNew: (UUID) -> Void
    var onToggleLibrary: (() -> Void)?
    var isLibraryVisible = true
    var isSearchFocused: Binding<Bool>?
    @FocusState private var searchFocused: Bool
    @State private var filing: NoteCardSnapshot?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        List {
            Group {
                mastheadRow
                searchField
                if model.isStream, !model.isSearching {
                    chips
                } else if !model.isSearching {
                    pagesHeader
                }
                content
                Color.clear.frame(height: layout.contentBottomInset)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: Space.x3, trailing: layout.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(LifeOSTokens.canvas.resolve(scheme))
        .foregroundStyle(primary)
        .sheet(item: $filing) { card in
            NoteFilingSheet(
                targets: model.moveTargets(), currentBucket: card.isInInbox ? nil : card.bucket, currentFolderID: card.folderID,
                onPick: { model.move(card.id, to: $0.bucket, folderID: $0.folderID) },
                onCreateFolder: { model.makeFolder(named: $0, in: $1) }
            )
        }
        .onChange(of: isSearchFocused?.wrappedValue ?? false) { _, wanted in
            if wanted { searchFocused = true }
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused { isSearchFocused?.wrappedValue = false }
        }
    }

    // MARK: Rows above the cards

    private var mastheadRow: some View {
        HStack(alignment: .top, spacing: Space.x2) {
            if let onToggleLibrary {
                Button(action: onToggleLibrary) {
                    Image(systemName: "sidebar.leading")
                }
                .buttonStyle(.editorial(.secondary, size: .compact))
                .accessibilityLabel(isLibraryVisible ? "Hide library" : "Show library")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            EditorialMasthead(eyebrow: NotesHeadline.eyebrow(model.scope, count: model.headerCount),
                              title: model.headerTitle)
            Button("New") { open(model.createNote(kind: .note), isNew: true) }
                .buttonStyle(.editorial(.primary, size: .compact))
                .accessibilityLabel("New page")
                .accessibilityHint("Starts a page in your Inbox")
        }
        .padding(.top, Space.x2)
    }

    private var searchField: some View {
        HairlineField(text: $model.query, placeholder: "Search all pages", focus: $searchFocused)
    }

    private var chips: some View {
        UnderlinePicker(
            selection: Binding(get: { model.selection.streamChip ?? .inbox },
                               set: { model.selection = NoteSelection(chip: $0) }),
            options: [(NoteStreamChip.inbox, "Inbox"), (.all, "All"), (.todos, "To-dos")]
        )
    }

    private var pagesHeader: some View {
        EditorialSectionHeader(title: "Pages") {
            HStack(spacing: Space.x1) {
                if model.selection.bucket != nil || model.selection.folderID != nil {
                    Menu {
                        Picker("Page type", selection: $model.filter) {
                            ForEach(NoteShelfFilter.allCases) { filter in
                                Label(filter.title, systemImage: filter.systemImage).tag(filter)
                            }
                        }
                    } label: {
                        Text(model.filter.title)
                    }
                    .buttonStyle(.editorial(.secondary, size: .compact))
                    .accessibilityLabel("Filter pages")
                }
                Menu {
                    Picker("Sort pages", selection: $model.sort) {
                        ForEach(NoteSort.allCases) { sort in
                            Label(sort.title, systemImage: sort.systemImage).tag(sort)
                        }
                    }
                } label: {
                    Text(model.sort.title)
                }
                .buttonStyle(.editorial(.secondary, size: .compact))
                .accessibilityLabel("Sort: \(model.sort.title)")
            }
        }
    }

    // MARK: The rows

    @ViewBuilder
    private var content: some View {
        if model.selection == .todos, !model.isSearching {
            if model.tasks.isEmpty {
                Text("No open to-dos.").font(LifeOSType.secondary).foregroundStyle(quiet)
            }
            ForEach(model.tasks) { group in
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(group.page.title).font(LifeOSType.caption).foregroundStyle(quiet).lineLimit(1)
                    ChecklistRows(rows: group.rows,
                                  onTick: { row in
                                      if case .page(let documentID, let blockID) = row.source {
                                          model.toggleTask(documentID: documentID, blockID: blockID)
                                      }
                                  },
                                  onOpen: { _ in onOpen(group.page.id) })
                }
            }
        } else if model.cards.isEmpty {
            emptyState
        } else {
            ForEach(model.cards) { card in
                VStack(spacing: 0) {
                    NoteCard(card: card, isOpen: card.id == openPageID,
                        onOpen: { onOpen(card.id) },
                        onFavorite: { model.toggleFavorite(card.id) },
                        onArchive: { model.toggleArchive(card.id) },
                        onDelete: { model.delete(card.id) },
                        moveTargets: model.moveTargets(),
                        onMove: { model.move(card.id, to: $0.bucket, folderID: $0.folderID) })
                    Hairline()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("File", systemImage: "tray.and.arrow.down") { filing = card }
                        .tint(LifeOSTokens.primaryText.resolve(scheme))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(card.isArchived ? "Restore" : "Archive",
                           systemImage: card.isArchived ? "tray.and.arrow.up" : "archivebox") {
                        model.toggleArchive(card.id)
                    }
                    .tint(Editorial.quietInk(scheme))
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isSearching {
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("No matching pages").font(LifeOSType.rowTitle)
                Text("Try another title or a word from your notes.")
                    .font(LifeOSType.secondary).foregroundStyle(quiet)
                Button("Clear search") { model.query = "" }
                    .buttonStyle(.editorial(.secondary, size: .compact))
            }
            .editorialCard()
        } else if model.selection == .inbox {
            EditorialEmptyState(
                sentence: "Nothing waiting. New starts a page here.",
                action: "New page",
                onAction: { open(model.createNote(kind: .note), isNew: true) }
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialRow("A thought worth keeping", value: "Just now")
                    EditorialRow("Call the dentist", value: "To-do")
                }
            }
        } else {
            EditorialEmptyState(
                sentence: "Pages, journals and task lists, all in one place.",
                action: "New page",
                onAction: { open(model.createNote(kind: .note), isNew: true) }
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialRow("Monday journal", value: "Today")
                    EditorialRow("Groceries", value: "3 of 8")
                    EditorialRow("Ideas for the trip", value: "Yesterday")
                }
            }
        }
    }

    private func open(_ id: UUID?, isNew: Bool = false) {
        guard let id else { return }
        if isNew { onOpenNew(id) } else { onOpen(id) }
    }
}
```

`NoteCardSnapshot` is `Identifiable`, so `.sheet(item: $filing)` works.

- [ ] **Step 4: Delete the old Inbox screen**

```bash
git rm LIfeOS/Features/Notes/View/NoteInboxScreen.swift LIfeOS/Features/Notes/ViewModel/NoteInboxViewModel.swift
grep -rn "NoteInboxScreen\|NoteInboxViewModel\|FilingSheet(" LIfeOS/ | grep -v NoteFilingSheet
```

Expected: no hits.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Notes/View/NoteShelfScreen.swift LIfeOS/Features/Notes/View/NoteFilingSheet.swift LIfeOS/Features/Notes/View/NoteCard.swift
git commit -m "feat(notes): the shelf opens on the Inbox, with chips, one-tap New and swipe to file

A List on paper so cards carry File and Archive swipes; Inbox, All and
To-dos as the calendar's underline switch; To-dos as the day screen's
checklist rows grouped by page; cards say Journal or Tasks and Inbox;
the old unrouted Inbox screen goes and its picker returns as
NoteFilingSheet with nested folders and New folder."
```

---

### Task 5: The editor says where a page lives, and opens ready to write

**Files:**
- Modify: `LIfeOS/Features/Notes/ViewModel/NoteEditorViewModel.swift`, `LIfeOS/Features/Notes/View/NoteEditorScreen.swift`

**Interfaces:**
- Consumes: `NoteFilingSheet` (Task 4), `NoteEditorFocus` (Task 3), `NotesStore.move`, `createFolder`, `snapshot().moveTargets()`.
- Produces: on the view model `folderID`, `folderName`, `isInInbox`, `fileLabel`, `file(to:folderID:)`, `createFolder(named:in:) -> UUID?`, `moveTargets()`; `NoteEditorScreen(model:focusOnAppear:onOpenLinked:onClose:)` with `openFilingOnAppear`.

- [ ] **Step 1: The view model**

(a) After `private(set) var bucket: NoteBucket = .projects`, add:

```swift
    private(set) var folderID: UUID?
    private(set) var folderName: String?
    /// Unfiled and not archived: the File chip reads `Inbox`.
    private(set) var isInInbox = false
```

(b) In `load()`, after `bucket = document.bucket`, add:

```swift
        folderID = document.folderID
        folderName = document.folderID.flatMap { try? store.folder(id: $0)?.name }
        isInInbox = document.isInInbox
```

(c) After `load()`, add:

```swift
    /// `Inbox`, `Projects`, or `Projects · Training`: what the chip reads.
    var fileLabel: String {
        if isInInbox { return "Inbox" }
        if let folderName { return "\(bucket.title) · \(folderName)" }
        return bucket.title
    }

    /// Files the page. Choosing a home is what takes a page out of the Inbox.
    func file(to bucket: NoteBucket, folderID: UUID?) {
        mutate { store, document in try store.move(document, to: bucket, folderID: folderID) }
        self.bucket = bucket
        self.folderID = folderID
        folderName = folderID.flatMap { try? store?.folder(id: $0)?.name }
        isInInbox = false
    }

    /// A folder made from the filing sheet, so a page can be put somewhere
    /// that did not exist a moment ago.
    func createFolder(named name: String, in bucket: NoteBucket) -> UUID? {
        guard let store else { return nil }
        let folder = try? store.createFolder(name: name, bucket: bucket)
        requestSync()
        return folder?.id
    }

    func moveTargets() -> [NoteMoveTarget] {
        (try? store?.snapshot().moveTargets()) ?? []
    }
```

- [ ] **Step 2: The screen**

(a) Replace the stored properties at the top (lines 12 to 14) with:

```swift
    @Bindable var model: NoteEditorViewModel
    /// What to focus once the page is up: the title for a page just made.
    var focusOnAppear: NoteEditorFocus = .none
    /// Previews open the filing sheet straight away to draw it.
    var openFilingOnAppear = false
    var onOpenLinked: (UUID) -> Void
    var onClose: (() -> Void)?
```

and add, after `@State private var confirmClearDrawing = false`:

```swift
    @State private var showFiling = false
    @FocusState private var titleFocused: Bool
```

(b) The title field (lines 146 to 150) becomes:

```swift
            TextField("Untitled", text: $model.title, axis: .vertical)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(primary)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($titleFocused)
```

(c) `metadata` (lines 170 to 188) becomes:

```swift
    @ViewBuilder private var metadata: some View {
        Button { showFiling = true } label: {
            Label(model.fileLabel, systemImage: model.isInInbox ? "tray" : "folder")
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
        .accessibilityHint("Choose where this page lives")
        if let date = model.entryDate {
            Text(date, format: .dateTime.month(.abbreviated).day())
        }
        if model.kind == .task {
            Menu {
                ForEach(PlanStatus.allCases, id: \.self) { status in
                    Button(status.title) { model.setStatus(status) }
                }
            } label: { Label(model.status.title, systemImage: "circle.dotted") }
        }
        Button { model.flush() } label: {
            Label(model.saveMessage, systemImage: model.hasSaveError ? "exclamationmark.circle" : "checkmark")
        }
        .buttonStyle(.plain)
        .disabled(!model.hasSaveError)
        .accessibilityHint(model.hasSaveError ? "Retry saving this page" : "")
    }
```

(d) On the `header` (after its `.sheet(isPresented: $showEmojiPicker)`), add:

```swift
        .sheet(isPresented: $showFiling) {
            NoteFilingSheet(
                targets: model.moveTargets(),
                currentBucket: model.isInInbox ? nil : model.bucket, currentFolderID: model.folderID,
                onPick: { model.file(to: $0.bucket, folderID: $0.folderID) },
                onCreateFolder: { model.createFolder(named: $0, in: $1) }
            )
        }
        .onAppear {
            switch focusOnAppear {
            case .title: titleFocused = true
            case .firstBlock: model.focusedBlockID = model.blocks.first?.id
            case .none: break
            }
            if openFilingOnAppear { showFiling = true }
        }
```

- [ ] **Step 3: Build the app**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task5.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task5.log | head -8
```

Expected: `build exit 0`. The likely first errors are the `.page` pattern sites in `NotesHubScreen` and `NotesDesignPreview`'s `NoteEditorScreen(model:onOpenLinked:)` call, which still compiles because `focusOnAppear` has a default.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Notes/ViewModel/NoteEditorViewModel.swift LIfeOS/Features/Notes/View/NoteEditorScreen.swift
git commit -m "feat(notes): the editor's File chip, and a new page that opens on its title

The meta row's first item says Inbox or the shelf and folder and opens
the filing picker; a page New just made opens with the title focused."
```

---

### Task 6: Preview pages

**Files:**
- Modify: `LIfeOS/Features/Today/View/TodayDesignPreview.swift`, `LIfeOS/Features/Notes/View/NotesDesignPreview.swift`, `LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift`

- [ ] **Step 1: The shelf pages**

In `TodayDesignPreview.swift`:

(a) The doc comment's `notes` entry becomes `notes` (the shelf; `--scope=inbox|all|todos|favorites`), `notes-empty`.

(b) In `TodayFixture.init()`, after `notes.attach(container.mainContext)` and before `notes.load()`, the day-briefing PR already seeds `Groceries` with to-dos and today's journal; add one more unfiled page with a to-do so the To-dos chip shows two groups:

```swift
        if let marathon = try? NotesStore(context: container.mainContext).document(titled: "Marathon block, week four") {
            try? NotesStore(context: container.mainContext).update(marathon, blocks: [
                NoteBlock(text: "Long run moved to Sunday. Calf held up."),
                NoteBlock(kind: .todo, text: "Book the physio"),
            ])
        }
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--scope=") })?.dropFirst(8) {
            switch String(raw) {
            case "all": notes.selection = .all
            case "todos": notes.selection = .todos
            case "favorites": notes.selection = .favorites
            default: notes.selection = .inbox
            }
        }
```

(c) The `notes` and `notes-empty` cases lose `onNewFolder: { _ in }` and gain `onOpenNew: { _ in }`:

```swift
            case "notes":
                NavigationStack { NoteShelfScreen(model: fixture.notes, onOpen: { _ in }, onOpenNew: { _ in }).shellToolbar() }
                    .modelContainer(fixture.container)
            case "notes-empty":
                NavigationStack { NoteShelfScreen(model: fixture.emptyNotes, onOpen: { _ in }, onOpenNew: { _ in }).shellToolbar() }
                    .modelContainer(fixture.emptyContainer)
```

- [ ] **Step 2: The editor pages**

In `NotesDesignPreview.swift`, replace the struct's stored properties and body with:

```swift
struct NotesDesignPreview: View {
    var showEditor = false
    var showsPreviewLabel = true
    /// `notes-editor-new`: a blank page with the title focused;
    /// `notes-filing`: the sample page with the filing sheet up.
    var page: String = ""
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fixture = NotesPreviewFixture()

    var body: some View {
        Group {
            switch page {
            case "notes-editor-new":
                NavigationStack {
                    NoteEditorScreen(model: fixture.blankEditor, focusOnAppear: .title, onOpenLinked: { _ in })
                }
            case "notes-filing":
                NavigationStack {
                    NoteEditorScreen(model: fixture.editor, openFilingOnAppear: true, onOpenLinked: { _ in })
                }
            default:
                if showEditor {
                    NavigationStack {
                        NoteEditorScreen(model: fixture.editor, onOpenLinked: { _ in })
                            .navigationTitle("Preview page")
                    }
                } else {
                    NotesHubScreen(model: fixture.notes, plan: fixture.plan, onAddHabit: {})
                }
            }
        }
        .modelContainer(fixture.container)
        .environment(\.layout, .metrics(for: sizeClass == .regular ? .regular : .compact))
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsPreviewLabel, page.isEmpty {
                Text("DESIGN PREVIEW · SAMPLE PAGES")
                    .font(.caption2).tracking(1).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(LifeOSTokens.canvas.light)
            }
        }
    }
}
```

and in `NotesPreviewFixture` add `let blankEditor: NoteEditorViewModel` after `let editor`, and at the end of `init()`:

```swift
        let blank = try! store.createDocument(bucket: .projects)
        blankEditor = NoteEditorViewModel(documentID: blank.id)
        blankEditor.attach(context)
        blankEditor.load()
```

In `HealthActivityDesignPreview.swift`, after the line that routes the Today pages, add:

```swift
            else if page == "notes-editor-new" || page == "notes-filing" { NotesDesignPreview(page: page) }
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project LIfeOS.xcodeproj -scheme LIfeOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=B192EA65-BAA2-4814-A298-94A2F0C8FC87' -quiet > $OUT/build-task6.log 2>&1; echo "build exit $?"; grep "error:" $OUT/build-task6.log | head -5
```

Expected: `build exit 0`.

- [ ] **Step 4: Commit**

```bash
git add LIfeOS/Features/Today/View/TodayDesignPreview.swift LIfeOS/Features/Notes/View/NotesDesignPreview.swift LIfeOS/Features/Health/View/HealthActivityDesignPreview.swift
git commit -m "feat(notes): preview pages for the Inbox, the chips, the filing sheet and a new page"
```

---

### Task 7: Gates and captures

- [ ] **Step 1: Tests and typography**

```bash
(cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*(Test run with|recorded an issue)" | tail -2)
scripts/check-typography.sh > $OUT/typo-notes.txt 2>&1
diff <(sed 's/^[^:]*://' $OUT/typo-notes-base.txt | sort) <(sed 's/^[^:]*://' $OUT/typo-notes.txt | sort) | grep '^>' || echo "typography: no new violations"
```

Expected: the suite passes with five new tests (`NoteSnapshotTests` 1, `NotesStoreTests` 3, `NotesHeadlineTests` 1 more) and no new violations. `NoteFilingSheet` and the shelf use only `LifeOSType` and `Editorial`.

- [ ] **Step 2: Captures**

```bash
APP=$(for p in ~/Library/Developer/Xcode/DerivedData/LIfeOS-*/info.plist; do grep -q "worktrees/notes-inbox/" "$p" && echo "$(dirname "$p")/Build/Products/Debug-iphonesimulator/LIfeOS.app"; done | head -1)
SIM=B192EA65-BAA2-4814-A298-94A2F0C8FC87
xcrun simctl boot $SIM 2>/dev/null; xcrun simctl bootstatus $SIM -b >/dev/null 2>&1
xcrun simctl install $SIM "$APP"
capture() { local name=$1; shift
  xcrun simctl terminate $SIM com.shivvyas.lifeos 2>/dev/null
  xcrun simctl launch $SIM com.shivvyas.lifeos --design-preview "$@" >/dev/null
  perl -e 'select(undef,undef,undef,4)'
  xcrun simctl io $SIM screenshot "$OUT/pr-notes-$name.png" >/dev/null; }
capture inbox --page=notes
capture inbox-dark --page=notes --dark
capture all --page=notes --scope=all
capture todos --page=notes --scope=todos
capture favorites --page=notes --scope=favorites
capture empty --page=notes-empty
capture editor-new --page=notes-editor-new
capture filing --page=notes-filing
capture filing-dark --page=notes-filing --dark
ls -la $OUT/pr-notes-*.png
```

Check each with the Read tool:
- `inbox`: `NOTES · 2 IN INBOX` over `Inbox`, `New`, the field, the `Inbox | All | To-dos` switch, two cards (`Marathon block, week four` and `Groceries` with `TASKS`), each captioned `Inbox`; the journal is absent (it is filed in the Journal folder).
- `all`: `NOTES · 3 PAGES` over `All pages`, three cards including the journal with `JOURNAL` and `Journal` as its caption.
- `todos`: `NOTES · 3 TO-DOS` (or the live count) over `To-dos`, two groups titled by page with checkbox rows.
- `favorites`: `NOTES · NO FAVOURITES`, the generic empty state.
- `empty`: `NOTES · NOTHING IN INBOX`, the Inbox empty state with `New page`.
- `editor-new`: an untitled page with the caret in the title and the keyboard up; the meta row's first item reads `Inbox` with a tray.
- `filing`: the editor behind the `File` sheet listing `On Projects`, `Ideas & projects`, `On Areas`, `Personal`, `On Research`, and the `New folder` section with its field, segmented shelf picker and `Create and file here`.

- [ ] **Step 3: Simulator checks**

From `--page=notes`: swipe a card right and screenshot (the `File` action); from `--page=notes-filing`: tap `Personal` and screenshot the chip reading `Areas · Personal`; from `--page=notes --scope=todos`: tap a square and screenshot (the row struck, the count down by one). Use the simulator memory's recipe; if two taps in a row leave the screen unchanged, stop and say so in the PR.

---

### Task 8: Open the pull request

- [ ] **Step 1: Rebase, re-run, push**

```bash
git fetch origin && git rebase origin/main && (cd LifeOSKit && swift test 2>&1 | grep -E "^[^|]*Test run with" | tail -1)
git push -u origin feat/notes-inbox
```

- [ ] **Step 2: The PR**

`gh pr create --base main --title "feat(notes): the tab opens on an Inbox, New is one tap, and the editor files its page" --body-file $OUT/pr-notes-body.md`, the body in the house style (`## Summary`, `## Verification`, `## Deferred minors`, the spec and plan paths, PR 1 of 3). No attribution footer.

- [ ] **Step 3: Memory**

Update `day-briefing-and-notes-brainstorm.md`: PR 1 of the Notes work is PR #N; next is the editor PR (spec section 2).
