# Notes Phone Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the phone's Library-first notes shell with an Inbox stream and a pinned composer, so capturing one thought costs one tap instead of four.

**Architecture:** Everything queryable goes into `NotesStore` in the `Persistence` package, where it has tests: a `capture` write that lands a line of text unfiled, and a `stream(for:)` read that routes a chip to the rows it shows. The app layer is then a thin view model plus one screen, verified by building, because the app target has no test target. `NotesHubScreen.wideShell` is not touched: the iPad keeps its three column arrangement.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Package at `LifeOSKit/`, app at `LIfeOS/`.

**Spec:** `docs/superpowers/specs/2026-08-27-mobile-notes-redesign-design.md`, phase 2 ("Phone shell") of six.

## Global Constraints

- Work in the worktree `.claude/worktrees/notes-phone-shell` on branch `feat/notes-phone-shell`, branched from `main` at 4f98aba. Other Claude sessions share `/Users/shivvyas/LIfeOS` and move HEAD there.
- Package tests: `swift test --package-path LifeOSKit --filter <SuiteName>`. Full run: `swift test --package-path LifeOSKit`.
- App build: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`. The app has **no test target**; app-layer tasks are verified by a clean build.
- Typography: never write a raw `.font(.system(...))`. Use `LifeOSType`. `scripts/check-typography.sh` fails otherwise. Available steps: `caption`, `eyebrow`, `label`, `secondary`, `body`, `rowTitle`, `sectionTitle`, `screenTitle`, `display`.
- A missing value is `nil`, never `0`.
- Commit style: `type(scope): imperative summary` with a short body. No em dashes in commit messages. No AI attribution of any kind.
- **`wideShell` is out of scope.** Do not edit it, and do not change anything it depends on in a way that alters how it renders. The iPad arrangement ships unchanged.

## Scope: what phase 2 delivers and what it cannot

The spec's phase 2 description names several things that depend on later phases and **must not** be built here, because the types they need do not exist:

| Spec mentions | Phase that builds it | This plan |
|---|---|---|
| Goals chip in the chip row | 4 | Omitted |
| Collection chips, `#` autocomplete in the composer | 3 | Omitted |
| Mic button on the composer | 6 | Omitted |
| Map button in the header | 5 | Omitted |
| Swipe right files to "recent collections and shelves" | 3 for collections | Files to a shelf or folder only |

The chip row is therefore **Inbox, All, To-dos**. The composer carries **text, a to-do toggle, and a sketch button**. The header carries **Library** only. Everything else in the phase 2 description ships as written.

---

### Task 1: Capture a line of text into the Inbox

The composer's whole job. A captured thought is a document with no title, one block, and no `filedAt`, which is what `NoteDocument.isInInbox` already keys on.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NotesStore.swift` (add to the writing section, after `createDocument`)
- Test: `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift`

**Interfaces:**
- Consumes: `createDocument(title:kind:bucket:folderID:blocks:entryDate:dueDate:status:) throws -> NoteDocument`, `NoteBlock(id:kind:text:isChecked:indent:drawing:sketchHeight:dueDate:goalID:)`, `NoteDocument.isInInbox`, `NoteDocument.displayTitle`.
- Produces: `NotesStore.capture(_ text: String, isTodo: Bool = false) throws -> NoteDocument?`. Returns nil for text that is empty once trimmed, so the composer can bind Return unconditionally without guarding.

- [ ] **Step 1: Write the failing test**

Append to `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift`, inside the existing suite. Match the suite's existing store-construction helper rather than building a container inline; read the top of the file first and use whatever it already provides.

```swift
    @Test func captureLandsAThoughtInTheInbox() throws {
        let store = try makeStore()
        let captured = try #require(try store.capture("Ring the dentist"))

        #expect(captured.isInInbox)
        #expect(try store.inbox().map(\.id).contains(captured.id))
    }

    /// The title is left empty on purpose: `displayTitle` already falls back
    /// to the first textual block, so writing the text into both would show
    /// the same sentence twice on the card.
    @Test func aCapturedThoughtTakesItsTitleFromItsOnlyLine() throws {
        let store = try makeStore()
        let captured = try #require(try store.capture("Ring the dentist"))

        #expect(captured.title.isEmpty)
        #expect(captured.blocks.count == 1)
        #expect(captured.blocks.first?.text == "Ring the dentist")
        #expect(captured.displayTitle == "Ring the dentist")
    }

    @Test func captureCanMakeAToDoRatherThanAParagraph() throws {
        let store = try makeStore()
        let paragraph = try #require(try store.capture("A thought"))
        let todo = try #require(try store.capture("A task", isTodo: true))

        #expect(paragraph.blocks.first?.kind == .paragraph)
        #expect(todo.blocks.first?.kind == .todo)
        #expect(todo.blocks.first?.isChecked == false)
    }

    /// Return on an empty composer must be a no-op, not a blank page in the
    /// stream. Returning nil rather than throwing lets the composer bind
    /// Return unconditionally.
    @Test func captureIgnoresTextThatIsOnlyWhitespace() throws {
        let store = try makeStore()
        #expect(try store.capture("   \n  ") == nil)
        #expect(try store.inbox().isEmpty)
    }

    @Test func captureTrimsTheEdgesOfWhatWasTyped() throws {
        let store = try makeStore()
        let captured = try #require(try store.capture("  Ring the dentist  "))
        #expect(captured.blocks.first?.text == "Ring the dentist")
    }

    /// A captured to-do must reach the task index, or the To-dos chip would
    /// not show a thought captured as a task.
    @Test func aCapturedToDoIsIndexedAsATask() throws {
        let store = try makeStore()
        let captured = try #require(try store.capture("A task", isTodo: true))

        let tasks = try store.indexedTasks(openOnly: true)
        #expect(tasks.contains { $0.documentID == captured.id && $0.text == "A task" })
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter PersistenceTests.NotesStoreTests`
Expected: FAIL, `value of type 'NotesStore' has no member 'capture'`.

- [ ] **Step 3: Write minimal implementation**

Add to `LifeOSKit/Sources/Persistence/NotesStore.swift`, immediately after `createDocument`:

```swift
    /// One line of text, straight into the Inbox.
    ///
    /// The title is deliberately left empty: `NoteDocument.displayTitle`
    /// already falls back to the first textual block, so a captured thought
    /// reads correctly on a card without storing the same sentence twice.
    ///
    /// `filedAt` is untouched, which is what puts the page in the Inbox.
    /// Filing it later through `move(_:to:folderID:)` is what stamps it and
    /// takes it out again.
    ///
    /// Returns nil for text that is empty once trimmed, so the composer can
    /// bind Return unconditionally instead of guarding at the call site.
    @discardableResult
    public func capture(_ text: String, isTodo: Bool = false) throws -> NoteDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return try createDocument(
            bucket: .areas,
            blocks: [NoteBlock(kind: isTodo ? .todo : .paragraph, text: trimmed)]
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path LifeOSKit --filter PersistenceTests`
Expected: PASS, including every pre-existing case in the target.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NotesStore.swift LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift
git commit -m "feat(notes): capture a line of text straight into the Inbox

The composer's whole job. No title, one block, no filedAt, which is what
isInInbox already keys on. Empty text returns nil rather than throwing so
Return can be bound unconditionally."
```

---

### Task 2: Route a chip to the rows it shows

The chip row needs one place that decides what each chip means, and it needs to be testable, which rules out putting it in the view.

**Files:**
- Create: `LifeOSKit/Sources/Persistence/NoteStream.swift`
- Modify: `LifeOSKit/Sources/Persistence/NotesStore.swift` (add `stream(for:)` beside the other reads)
- Test: `LifeOSKit/Tests/PersistenceTests/NoteStreamTests.swift`

**Interfaces:**
- Consumes: `NotesStore.inbox() throws -> [NoteCardSnapshot]`, `NotesStore.cards(...)`, `NotesStore.documents(includeArchived:)`, `NotesStore.indexedTasks(openOnly:) throws -> [NoteTask]`.
- Produces: `NoteStreamChip` (`.inbox`, `.all`, `.todos`) with `title: String` and `static let all: [NoteStreamChip]`; `NoteStream` (`.cards([NoteCardSnapshot])`, `.tasks([NoteTask])`) with `isEmpty: Bool`; and `NotesStore.stream(for: NoteStreamChip) throws -> NoteStream`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/NoteStreamTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NoteStreamTests {
    private func makeStore() throws -> NotesStore {
        NotesStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    @Test func theChipRowReadsInboxAllToDos() {
        #expect(NoteStreamChip.all == [.inbox, .all, .todos])
        #expect(NoteStreamChip.inbox.title == "Inbox")
        #expect(NoteStreamChip.all.first?.title == "Inbox")
        #expect(NoteStreamChip.todos.title == "To-dos")
    }

    @Test func theInboxChipShowsOnlyWhatIsUnfiled() throws {
        let store = try makeStore()
        let loose = try #require(try store.capture("Still loose"))
        let filed = try #require(try store.capture("Filed away"))
        try store.move(filed, to: .projects, folderID: nil)

        guard case .cards(let cards) = try store.stream(for: .inbox) else {
            Issue.record("inbox should be cards")
            return
        }
        #expect(cards.map(\.id) == [loose.id])
    }

    @Test func theAllChipShowsFiledAndUnfiledAlike() throws {
        let store = try makeStore()
        let loose = try #require(try store.capture("Still loose"))
        let filed = try #require(try store.capture("Filed away"))
        try store.move(filed, to: .projects, folderID: nil)

        guard case .cards(let cards) = try store.stream(for: .all) else {
            Issue.record("all should be cards")
            return
        }
        #expect(Set(cards.map(\.id)) == Set([loose.id, filed.id]))
    }

    /// Newest first: the stream is what you just captured, not what you
    /// captured first.
    @Test func aStreamOfCardsIsNewestFirst() throws {
        let store = try makeStore()
        let first = try #require(try store.capture("First"))
        let second = try #require(try store.capture("Second"))
        // Written after `first`, so it must sort ahead of it.
        try store.rename(second, to: "Second")

        guard case .cards(let cards) = try store.stream(for: .all) else {
            Issue.record("all should be cards")
            return
        }
        #expect(cards.first?.id == second.id)
        #expect(cards.last?.id == first.id)
    }

    @Test func theToDosChipShowsOpenTasksAcrossPages() throws {
        let store = try makeStore()
        _ = try store.capture("A plain thought")
        let task = try #require(try store.capture("A task", isTodo: true))

        guard case .tasks(let tasks) = try store.stream(for: .todos) else {
            Issue.record("todos should be tasks")
            return
        }
        #expect(tasks.map(\.documentID) == [task.id])
    }

    @Test func anArchivedPageLeavesEveryStream() throws {
        let store = try makeStore()
        let captured = try #require(try store.capture("Gone"))
        try store.archive(captured)

        guard case .cards(let inbox) = try store.stream(for: .inbox),
              case .cards(let all) = try store.stream(for: .all) else {
            Issue.record("both should be cards")
            return
        }
        #expect(inbox.isEmpty)
        #expect(all.isEmpty)
    }

    @Test func anEmptyStreamSaysSoWhicheverShapeItIs() {
        #expect(NoteStream.cards([]).isEmpty)
        #expect(NoteStream.tasks([]).isEmpty)
    }
}
```

**Note for the implementer:** `NotesStore.rename(_:to:)` is used above only to bump `updatedAt` so the ordering test has two distinguishable timestamps. If `updatedAt` does not move on rename, or if the two captures land on the same instant and the ordering assertion is flaky, say so in your report and use whatever the store's own tests already do to advance a timestamp. Do not delete the ordering assertion.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path LifeOSKit --filter PersistenceTests.NoteStreamTests`
Expected: FAIL, `cannot find 'NoteStreamChip' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `LifeOSKit/Sources/Persistence/NoteStream.swift`:

```swift
import Foundation

/// A filter across the whole library, as opposed to `NoteSelection`, which
/// picks one shelf or folder.
///
/// Deliberately small. The spec's Goals chip and the person's own collection
/// chips arrive with the phases that build those models; adding cases here
/// before then would mean a chip that routes to nothing.
public enum NoteStreamChip: String, Sendable, CaseIterable, Equatable, Identifiable {
    case inbox, all, todos

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .all:   "All"
        case .todos: "To-dos"
        }
    }

    /// Reading order in the chip row. Kept separate from `allCases` so that
    /// adding a chip later cannot silently reshuffle the row.
    public static let all: [NoteStreamChip] = [.inbox, .all, .todos]
}

/// What a chip resolves to. Two shapes because to-dos are rows mirrored out
/// of blocks, not pages, and flattening them into cards would lose the one
/// thing that makes the chip worth having: which page each came from.
public enum NoteStream: Sendable {
    case cards([NoteCardSnapshot])
    case tasks([NoteTask])

    public var isEmpty: Bool {
        switch self {
        case .cards(let cards): cards.isEmpty
        case .tasks(let tasks): tasks.isEmpty
        }
    }
}
```

Then add to `LifeOSKit/Sources/Persistence/NotesStore.swift`, beside `inbox()`:

```swift
    /// The rows one chip shows. The single place a chip's meaning lives, so
    /// the view never decides what "All" includes.
    public func stream(for chip: NoteStreamChip) throws -> NoteStream {
        switch chip {
        case .inbox:
            return .cards(try inbox())

        case .all:
            let names = try folderNames()
            return .cards(
                try documents(includeArchived: false)
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .map { card($0, folderNames: names) }
            )

        case .todos:
            return .tasks(try indexedTasks(openOnly: true))
        }
    }
```

**Note for the implementer:** `folderNames()` and `card(_:folderNames:)` are the private helpers `inbox()` already uses; confirm their exact names in the file and match them. `NoteStream` is deliberately NOT `Equatable`: `NoteTask` is a `@Model` class and does not conform, so synthesised conformance would not compile. The tests below pattern-match instead of comparing whole values, which is why.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path LifeOSKit --filter PersistenceTests`
Expected: PASS, all suites in the target.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteStream.swift LifeOSKit/Sources/Persistence/NotesStore.swift LifeOSKit/Tests/PersistenceTests/NoteStreamTests.swift
git commit -m "feat(notes): route a chip to the rows it shows

One place decides what Inbox, All and To-dos mean, in the package where
it can be tested, rather than in the view. To-dos stay task rows instead
of being flattened into cards, which would lose the page each came from."
```

---

### Task 3: The inbox view model

**Files:**
- Create: `LIfeOS/Features/Notes/ViewModel/NoteInboxViewModel.swift`
- Test: none. The app target has no test target; every decision this makes is delegated to Task 1 and Task 2, which are tested.

**Interfaces:**
- Consumes: `NotesStore(context:)`, `capture(_:isTodo:)`, `stream(for:)`, `move(_:to:folderID:)`, `archive(_:)`, `document(id:)`, `NoteStreamChip`, `NoteStream`.
- Produces: `NoteInboxViewModel` with `chip: NoteStreamChip`, `stream: NoteStream`, `draft: String`, `isTodo: Bool`, and methods `attach(_:)`, `load()`, `capture() -> UUID?`, `file(_:to:folderID:)`, `archive(_:)`.

- [ ] **Step 1: Write the view model**

Create `LIfeOS/Features/Notes/ViewModel/NoteInboxViewModel.swift`:

```swift
import Foundation
import SwiftData
import Persistence

/// Drives the phone's notes shell.
///
/// Thin by the same rule as `LifeBoardViewModel`: what a chip means and what
/// a capture writes both live in `NotesStore`, where the app's lack of a test
/// target does not matter. This holds the draft, the selected chip, and the
/// rows last read.
@MainActor @Observable
final class NoteInboxViewModel {
    private(set) var stream: NoteStream = .cards([])

    var chip: NoteStreamChip = .inbox {
        didSet { if chip != oldValue { load() } }
    }

    /// What is in the composer right now. Cleared by `capture()` on success
    /// and left alone on failure, so a thought is never silently dropped.
    var draft: String = ""
    /// Whether the next capture becomes a to-do rather than a paragraph.
    /// Sticky across captures on purpose: someone logging three tasks should
    /// not have to press it three times.
    var isTodo: Bool = false

    private var context: ModelContext?
    private var store: NotesStore?

    func attach(_ context: ModelContext) {
        self.context = context
        self.store = NotesStore(context: context)
    }

    func load() {
        guard let store else { return }
        stream = (try? store.stream(for: chip)) ?? .cards([])
    }

    /// Writes the draft and returns the new page's id, so the caller can open
    /// it when the capture was a sketch rather than a sentence. Nil when
    /// there was nothing to write.
    @discardableResult
    func capture() -> UUID? {
        guard let store, let captured = try? store.capture(draft, isTodo: isTodo) else { return nil }
        draft = ""
        // A capture always belongs in the Inbox, so show it even if the
        // person was looking at another chip when they typed it.
        if chip != .inbox { chip = .inbox } else { load() }
        return captured?.id
    }

    /// A page holding one empty sketch block, opened straight away. Separate
    /// from `capture()` because a sketch has nothing typed to trim, and
    /// pushing it through the draft would file a paragraph reading "Sketch".
    @discardableResult
    func captureSketch() -> UUID? {
        guard let store else { return nil }
        let page = try? store.createDocument(
            bucket: .areas,
            blocks: [NoteBlock(kind: .sketch)]
        )
        load()
        return page?.id
    }

    func file(_ id: UUID, to bucket: NoteBucket, folderID: UUID?) {
        guard let store, let document = try? store.document(id: id) else { return }
        try? store.move(document, to: bucket, folderID: folderID)
        load()
    }

    func archive(_ id: UUID) {
        guard let store, let document = try? store.document(id: id) else { return }
        try? store.archive(document)
        load()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED. Nothing constructs this type yet, so a failure here is a signature mismatch against `NotesStore`; fix it against the real store rather than changing the store.

- [ ] **Step 3: Commit**

```bash
git add LIfeOS/Features/Notes/ViewModel/NoteInboxViewModel.swift
git commit -m "feat(notes): drive the phone shell from its own view model

Holds the draft, the chip and the rows last read. What a chip means and
what a capture writes both stay in NotesStore, where they are tested."
```

---

### Task 4: The inbox screen

**Files:**
- Create: `LIfeOS/Features/Notes/View/NoteInboxScreen.swift`
- Modify: `LIfeOS/Features/Notes/View/NotesHubScreen.swift` (`compactShell` only, around line 234)

**Interfaces:**
- Consumes: `NoteInboxViewModel` (Task 3), `NotesViewModel`, `NotesSidebar(snapshot:selection:query:isSearchFocused:onNewFolder:...)`, `NotesHubScreen.NoteRoute`, `NoteCardSnapshot`, `NoteTask`, `LifeOSType`, `LifeOSTokens`, `Space`, `Radius`, `\.layout`.

**A deviation to make deliberately, not by accident:** the stream uses `List` with `.listStyle(.plain)`, `.scrollContentBackground(.hidden)` and clear row backgrounds. `NotesSidebar`'s doc comment argues against `List` for the rail, and that reasoning stands there. Here it is the opposite call: swipe-to-file and swipe-to-archive are the spec's interaction, `swipeActions` only exists on `List` rows, and hand-rolling drag gestures to avoid a container is far more code and worse behaviour than styling one away. Put that reasoning in the file's doc comment.

- [ ] **Step 1: Write the screen**

Create `LIfeOS/Features/Notes/View/NoteInboxScreen.swift`:

```swift
import SwiftUI
import SwiftData
import DesignSystem
import Persistence

/// The notes tab on a phone.
///
/// Inbox first, not Library first. The complaint this answers is that writing
/// one line used to cost four taps: the tab, a shelf, the New menu, a page
/// kind. Here the composer is already on screen and Return keeps you in the
/// stream, so five thoughts are five sentences rather than five navigations.
///
/// Unlike `NotesSidebar`, which argues against `List` for good reasons, this
/// screen uses one: swipe to file and swipe to archive are the interaction the
/// stream is built around, `swipeActions` exists only on `List` rows, and
/// hand-rolling drag gestures to avoid the container would be more code and
/// worse behaviour than styling it away.
struct NoteInboxScreen: View {
    @Bindable var model: NoteInboxViewModel
    /// The library's own model, needed for the pushed Library screen and for
    /// the shelves a swipe files into.
    @Bindable var library: NotesViewModel
    var onOpen: (UUID) -> Void
    var onOpenLibrary: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.layout) private var layout
    @FocusState private var composerFocused: Bool
    /// `.sheet(item:)` needs `Identifiable` and `UUID` is not, so the page
    /// being filed is carried in a wrapper rather than raw.
    @State private var filing: FilingTarget?

    private var primary: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var secondary: Color { LifeOSTokens.secondaryText.resolve(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            chips
            rows
            composer
        }
        .background(LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea())
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Library", systemImage: "sidebar.left", action: onOpenLibrary)
            }
        }
        .sheet(item: $filing) { target in
            FilingSheet(snapshot: library.snapshot) { bucket, folderID in
                model.file(target.id, to: bucket, folderID: folderID)
                filing = nil
            }
        }
    }

    /// The page a swipe is filing. See `filing` above for why this exists.
    private struct FilingTarget: Identifiable {
        let id: UUID
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x1) {
                ForEach(NoteStreamChip.all) { chip in
                    let isOn = model.chip == chip
                    Button { model.chip = chip } label: {
                        Text(chip.title)
                            .font(LifeOSType.label.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? LifeOSTokens.canvas.resolve(scheme) : primary)
                            .padding(.horizontal, Space.x2)
                            .padding(.vertical, Space.half)
                            .background(
                                Capsule().fill(isOn ? primary : primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.vertical, Space.x1)
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch model.stream {
        case .cards(let cards):
            if cards.isEmpty {
                empty
            } else {
                List {
                    ForEach(cards) { card in
                        StreamRow(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(card.id) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading) {
                                Button("File", systemImage: "tray.and.arrow.down") {
                                    filing = FilingTarget(id: card.id)
                                }
                                .tint(LifeOSTokens.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Archive", systemImage: "archivebox", role: .destructive) {
                                    model.archive(card.id)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

        case .tasks(let tasks):
            if tasks.isEmpty {
                empty
            } else {
                List {
                    ForEach(tasks, id: \.id) { task in
                        TaskRow(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(task.documentID) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Space.half) {
            Spacer()
            Text(emptyLine)
                .font(LifeOSType.secondary)
                .foregroundStyle(secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Each chip's blank state says what would fill it, rather than all three
    /// saying "Nothing here".
    private var emptyLine: String {
        switch model.chip {
        case .inbox: "Nothing waiting. Write something below."
        case .all:   "No pages yet."
        case .todos: "No open to-dos."
        }
    }

    private var composer: some View {
        HStack(spacing: Space.x1) {
            Button {
                model.isTodo.toggle()
            } label: {
                Image(systemName: model.isTodo ? "checkmark.square.fill" : "square")
                    .foregroundStyle(model.isTodo ? LifeOSTokens.accent : secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isTodo ? "Capturing as a to-do" : "Capture as a to-do")

            TextField("Write something", text: $model.draft, axis: .vertical)
                .font(LifeOSType.body)
                .foregroundStyle(primary)
                .focused($composerFocused)
                .lineLimit(1...4)
                .onSubmit { model.capture() }
                .submitLabel(.return)

            Button {
                // A sketch has nothing to type, so it makes a page holding a
                // sketch block and opens it rather than going through the
                // draft, which would file a paragraph saying "Sketch".
                if let id = model.captureSketch() { onOpen(id) }
            } label: {
                Image(systemName: "scribble")
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New sketch")
        }
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, Space.x1)
        .background(
            LifeOSTokens.canvas.resolve(scheme)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// One page in the stream: what it is, what it says, and how far its to-dos
/// have got.
private struct StreamRow: View {
    let card: NoteCardSnapshot

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            Text(card.icon.isEmpty ? "\u{1F4C4}" : card.icon)
                .font(LifeOSType.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title.isEmpty ? "Untitled" : card.title)
                    .font(LifeOSType.rowTitle)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .lineLimit(1)

                if !card.excerpt.isEmpty {
                    Text(card.excerpt)
                        .font(LifeOSType.secondary)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .lineLimit(1)
                }

                HStack(spacing: Space.x1) {
                    if let folder = card.folderName {
                        Text(folder)
                    }
                    if card.taskCount > 0 {
                        Text("\(card.doneCount)/\(card.taskCount)")
                            .monospacedDigit()
                    }
                }
                .font(LifeOSType.caption)
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
        }
        .padding(.vertical, Space.half)
    }
}

/// One to-do, with the page it came from. The page matters: a to-do with no
/// context is a reminder, and this is not a reminders app.
private struct TaskRow: View {
    let task: NoteTask

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            Image(systemName: task.isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))

            Text(task.text.isEmpty ? "Untitled to-do" : task.text)
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .lineLimit(2)
        }
        .padding(.vertical, Space.half)
    }
}

/// Where a swiped page goes. Shelves and their folders, nothing else: the
/// person's own collections arrive with the phase that builds them.
private struct FilingSheet: View {
    let snapshot: NotesSnapshot
    let onPick: (NoteBucket, UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(NoteBucket.allCases.filter { $0 != .archive }) { bucket in
                    Section(bucket.title) {
                        Button("On \(bucket.title)") { onPick(bucket, nil) }
                        ForEach(snapshot.folders[bucket] ?? []) { folder in
                            Button(folder.name) { onPick(bucket, folder.id) }
                        }
                    }
                }
            }
            .navigationTitle("File")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
```

**Types used above, all verified against the source; use them as written:**
- `NotesSnapshot.folders` is `[NoteBucket: [NoteFolderSnapshot]]`, a dictionary keyed by bucket, so `snapshot.folders[bucket] ?? []` is correct and a flat filter would not compile (`NoteSnapshot.swift:93`).
- `NoteFolderSnapshot` is `Identifiable` with `id`, `name`, `icon`, `accent`, `bucket`, `parentID`, `count`, `children` (`NoteSnapshot.swift:64`). Nested folders are reachable through `children`; this sheet lists only the top level of each shelf, which is enough to file and keeps the sheet one screen tall.
- `LifeOSTokens.accent` takes NO `.resolve(scheme)`. `NoteAccessoryBar.swift:152` uses it bare, and that is the convention.
- `NoteCardSnapshot` carries `icon`, `title`, `excerpt`, `folderName`, `doneCount`, `taskCount` (`NoteSnapshot.swift:6`), which is every field `StreamRow` reads.

The one thing left open: if `Divider()` inside `.background` does not lay out against the composer's top edge, use a 1pt `Rectangle` filled with `secondary.opacity(0.15)` instead. Report which you used.

- [ ] **Step 2: Replace compactShell**

In `LIfeOS/Features/Notes/View/NotesHubScreen.swift`, replace the body of `compactShell` (around line 234) so the phone opens on the new screen and Library becomes a pushed route. Add a `library` case to `NoteRoute`, keep every existing case, and keep `.onChange(of: model.query)` behaviour by moving it onto the pushed Library screen.

```swift
    @State private var inbox = NoteInboxViewModel()

    private var compactShell: some View {
        NavigationStack(path: $path) {
            NoteInboxScreen(
                model: inbox,
                library: model,
                onOpen: { open($0) },
                onOpenLibrary: { path.append(.library) }
            )
            .padding(.bottom, layout.contentBottomInset)
            .background(LifeOSTokens.canvas.resolve(scheme))
            .navigationDestination(for: NoteRoute.self, destination: destination)
            .onAppear {
                inbox.attach(context)
                inbox.load()
            }
        }
    }
```

Add to `NoteRoute`:

```swift
        case library
```

And to `destination(_:)`:

```swift
        case .library:
            VStack(alignment: .leading, spacing: 0) {
                Text("Library")
                    .font(LifeOSType.display)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                    .padding(.horizontal, layout.gutter)
                    .padding(.top, 4)

                library
            }
            .background(LifeOSTokens.canvas.resolve(scheme))
            .onChange(of: model.query) { _, query in
                // Typing in the rail's search field should show results, and
                // results live on the shelf.
                if !query.isEmpty { path.append(.shelf) }
            }
```

**Verified, so do exactly this:** `NotesHubScreen` does NOT have a `ModelContext` of its own. The `@Environment(\.modelContext)` at line 356 belongs to the nested `NoteEditorHost`, not to the screen. Add `@Environment(\.modelContext) private var context` to `NotesHubScreen`'s own property block (alongside `@Environment(\.layout)` around line 25). The `library` computed property at line 205 already renders the rail; reuse it as written above rather than rebuilding it.

- [ ] **Step 3: Verify the build and the typography check**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

Run: `./scripts/check-typography.sh`
Expected: exit 0.

Run: `swift test --package-path LifeOSKit`
Expected: PASS.

- [ ] **Step 4: Confirm the iPad shell is untouched**

Run: `git diff --stat` and confirm the only changed region of `NotesHubScreen.swift` is `compactShell`, `NoteRoute`, `destination(_:)` and the new `@State`. `wideShell` and everything it calls must be byte-identical. Report the diff region.

- [ ] **Step 5: Commit**

```bash
git add LIfeOS/Features/Notes/View/NoteInboxScreen.swift LIfeOS/Features/Notes/View/NotesHubScreen.swift
git commit -m "feat(notes): open the phone on an Inbox stream and a composer

Writing one line used to cost four taps: the tab, a shelf, the New menu,
a page kind. The composer is now already on screen and Return keeps you
in the stream. The Library is a push away rather than the front door,
and the iPad's three column shell is untouched."
```

---

### Task 5: Verification

- [ ] **Step 1: Run the whole package suite**

Run: `swift test --package-path LifeOSKit`
Expected: PASS, every suite, no skips.

- [ ] **Step 2: Build the app clean**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' clean build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the typography check**

Run: `./scripts/check-typography.sh`
Expected: exit 0.

- [ ] **Step 4: Confirm what could not be verified here**

The app has no test target and no simulator is driven by this plan, so these remain unverified and must be reported as such rather than claimed:
- that Return actually keeps focus in the composer,
- that swipe-to-file and swipe-to-archive read correctly on a real row,
- that the chip row and composer do not collide with the keyboard,
- that the iPad shell still renders as it did.

State plainly which steps passed, with real output for anything that failed, and list the four above as outstanding.
