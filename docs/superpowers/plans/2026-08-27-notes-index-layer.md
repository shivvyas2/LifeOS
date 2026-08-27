# Notes Index Layer Implementation Plan (Phase 1 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make to-dos and wiki links answerable across the whole note library, without changing how notes are written, stored or synced.

**Architecture:** `NoteDocument` stays the single source of truth and blocks stay JSON inside `blocksData`. On every document save, `NoteIndexer` mirrors that JSON into derived SwiftData rows (`NoteTask`, `NoteLink`) inside the caller's existing transaction. Derived rows are local only, never pushed, and fully reconstructible by `rebuildAll()`, so an indexer bug is a stale view rather than data loss.

**Tech Stack:** Swift 6, SwiftData, swift-testing (`import Testing`), SwiftUI. Package: `LifeOSKit`, target `Persistence`.

**Spec:** `docs/superpowers/specs/2026-08-27-mobile-notes-redesign-design.md`

## Global Constraints

- Every `@Model` property carries a default value. SwiftData needs one to add a property to an existing store without a migration plan. See the comment on `NoteDocument`.
- No caller sets `updatedAt` by hand. `NotesStore.touch(_:)` stamps it, and forgetting that stamp is the one bug that silently stops sync.
- Derived rows are never pushed to Supabase. The wire format (`NoteDocumentRow` in `Integrations`) does not change in this phase.
- `reindex` never calls `context.save()`. It runs inside the caller's transaction so a document and its index can never be half written.
- Tests are swift-testing: `@Suite @MainActor struct`, `@Test func`, `#expect`. Not XCTest.
- Run tests from `LifeOSKit/` with `swift test --filter <SuiteName>`.
- No em dashes in commit messages. Conventional commits: `type(scope): imperative summary`.
- Work on branch `feat/notes-index-layer`, never on `main`.

## Deviation from the spec, decided here

The spec lists `NoteTagging` among the index layer models. It cannot ship in this phase: a tagging row points at a `NoteCollection`, and collections are phase 3. This plan delivers `NoteTask` and `NoteLink`; `NoteTagging` and the tag scanner move to the phase 3 plan, where the thing they reference exists. Nothing else in the spec's phase 1 changes.

---

### Task 1: To-do blocks carry a due date and a goal

A to-do's due date and its goal attachment are authored by a person, so they must live in the document. `NoteTask` is derived and rebuilt, and anything authored stored only on a derived row would be erased by the next reindex.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteBlock.swift:120-175` (the `NoteBlock` struct)
- Test: `LifeOSKit/Tests/PersistenceTests/NoteBlockTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NoteBlock.dueDate: Date?` and `NoteBlock.goalID: UUID?`, plus the extended memberwise `init` with both defaulting to `nil`.

- [ ] **Step 1: Write the failing test**

Add to `NoteBlockTests`:

```swift
/// Both fields are optional so a document written before they existed still
/// decodes. Synthesized Decodable uses decodeIfPresent for optionals, and
/// this is the test that keeps that true if the fields are ever reordered.
@Test func blocksWrittenBeforeDueDatesStillDecode() throws {
    let legacy = """
    [{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","kind":"todo",
      "text":"Book the flight","isChecked":false,"indent":0}]
    """.data(using: .utf8)!

    let blocks = try JSONDecoder().decode([NoteBlock].self, from: legacy)

    #expect(blocks.count == 1)
    #expect(blocks[0].text == "Book the flight")
    #expect(blocks[0].dueDate == nil)
    #expect(blocks[0].goalID == nil)
}

@Test func aTodoCarriesItsDueDateAndGoalThroughARoundTrip() throws {
    let goal = UUID()
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    let block = NoteBlock(kind: .todo, text: "Long run", dueDate: due, goalID: goal)

    let data = try JSONEncoder().encode([block])
    let decoded = try JSONDecoder().decode([NoteBlock].self, from: data)

    #expect(decoded[0].dueDate == due)
    #expect(decoded[0].goalID == goal)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter NoteBlockTests`
Expected: FAIL to compile, with "extra arguments 'dueDate', 'goalID' in call".

- [ ] **Step 3: Add the two fields**

In `NoteBlock`, after `sketchHeight`:

```swift
    /// When this to-do is meant to be done. To-do blocks only, and nil on
    /// every other kind. Authored, so it lives here rather than on the
    /// derived `NoteTask` row, which is rebuilt and would lose it.
    public var dueDate: Date?
    /// The goal this to-do counts towards, if any. Authored, for the same
    /// reason as `dueDate`.
    public var goalID: UUID?
```

Extend `init` with `dueDate: Date? = nil, goalID: UUID? = nil` as the last two parameters, and assign both.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NoteBlockTests`
Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteBlock.swift LifeOSKit/Tests/PersistenceTests/NoteBlockTests.swift
git commit -m "feat(notes): let a to-do carry a due date and a goal

Both are authored, so they belong in the document rather than on the
derived row the indexer will rebuild. Optional, so blocks written before
this decode unchanged."
```

---

### Task 2: The derived models

**Files:**
- Create: `LifeOSKit/Sources/Persistence/NoteIndex.swift`
- Modify: `LifeOSKit/Sources/Persistence/LifeOSContainer.swift:5-21` (the schema)
- Test: `LifeOSKit/Tests/PersistenceTests/NoteIndexTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NoteTask` with `id: UUID`, `documentID: UUID`, `text: String`, `isChecked: Bool`, `indent: Int`, `dueDate: Date?`, `goalID: UUID?`, `sortOrder: Int`. `NoteLink` with `sourceID: UUID`, `targetTitleFolded: String`, `targetID: UUID?`. Both registered in `LifeOSContainer.schema`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/NoteIndexTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NoteIndexTests {

    /// The derived models have to be in the schema or nothing can insert them.
    /// This is the cheapest possible check that they were registered, and it
    /// fails loudly rather than at first use on a device.
    @Test func derivedRowsCanBeStored() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let document = UUID()

        context.insert(NoteTask(id: UUID(), documentID: document, text: "Pack"))
        context.insert(NoteLink(sourceID: document, targetTitleFolded: "marathon"))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<NoteTask>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NoteLink>()).count == 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd LifeOSKit && swift test --filter NoteIndexTests`
Expected: FAIL to compile, with "cannot find 'NoteTask' in scope".

- [ ] **Step 3: Write the models**

Create `LifeOSKit/Sources/Persistence/NoteIndex.swift`:

```swift
import Foundation
import SwiftData

/// Derived rows: what the documents already say, in a shape that can be
/// queried.
///
/// Blocks live as JSON inside `NoteDocument.blocksData`, which is right for
/// editing and useless for asking "every open to-do". These models are that
/// JSON mirrored out by `NoteIndexer` on every save.
///
/// Two rules make them safe. They are never pushed, so two devices cannot
/// disagree about them. And every row is reconstructible from the documents,
/// so the repair for any inconsistency is `NoteIndexer.rebuildAll`, and the
/// worst an indexer bug can do is show a stale list.

/// One to-do block, hoisted out of its page.
@Model
public final class NoteTask {
    /// The block's own id, so the row is stable across reindexes rather than
    /// churning a new identity on every keystroke.
    ///
    /// Not unique on its own: a block copied and pasted into a second page
    /// keeps its id. Rows are scoped by `documentID` and rewritten a whole
    /// document at a time, so the pair is what identifies one to-do.
    public var id: UUID = UUID()
    public var documentID: UUID = UUID()
    public var text: String = ""
    public var isChecked: Bool = false
    public var indent: Int = 0
    public var dueDate: Date?
    public var goalID: UUID?
    /// Position in its page, so a cross note list can still show a page's
    /// to-dos in the order they were written.
    public var sortOrder: Int = 0

    public init(
        id: UUID = UUID(),
        documentID: UUID,
        text: String = "",
        isChecked: Bool = false,
        indent: Int = 0,
        dueDate: Date? = nil,
        goalID: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.documentID = documentID
        self.text = text
        self.isChecked = isChecked
        self.indent = indent
        self.dueDate = dueDate
        self.goalID = goalID
        self.sortOrder = sortOrder
    }
}

/// One `[[wiki link]]` edge. The mindmap's edge set, and what the backlinks
/// list will read once it stops rescanning every document.
@Model
public final class NoteLink {
    public var sourceID: UUID = UUID()
    /// Lowercased, so `[[Marathon]]` and `[[marathon]]` are one edge. What was
    /// typed stays in the block; only the lookup key is folded.
    public var targetTitleFolded: String = ""
    /// Nil when the link points at a page that does not exist yet. Obsidian
    /// calls these unresolved, and they are worth keeping: a link written
    /// before its page is a to-do of its own.
    public var targetID: UUID?

    public init(sourceID: UUID, targetTitleFolded: String, targetID: UUID? = nil) {
        self.sourceID = sourceID
        self.targetTitleFolded = targetTitleFolded
        self.targetID = targetID
    }
}
```

- [ ] **Step 4: Register both in the schema**

In `LifeOSContainer.schema`, after `NoteFolder.self`:

```swift
        NoteTask.self,
        NoteLink.self,
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd LifeOSKit && swift test --filter NoteIndexTests`
Expected: PASS, 1 test.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteIndex.swift LifeOSKit/Sources/Persistence/LifeOSContainer.swift LifeOSKit/Tests/PersistenceTests/NoteIndexTests.swift
git commit -m "feat(notes): add the derived task and link rows

Blocks stay JSON in the document. These are that JSON mirrored into a
shape a query can reach, local only and rebuildable, so they can never be
the only copy of anything."
```

---

### Task 3: The indexer mirrors to-dos

**Files:**
- Create: `LifeOSKit/Sources/Persistence/NoteIndexer.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift`

**Interfaces:**
- Consumes: `NoteTask`, `NoteLink` from Task 2. `NoteBlock.dueDate`/`goalID` from Task 1.
- Produces: `@MainActor public enum NoteIndexer` with `static func reindex(_ document: NoteDocument, in context: ModelContext) throws`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NoteIndexerTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    private func tasks(in context: ModelContext) throws -> [NoteTask] {
        try context.fetch(
            FetchDescriptor<NoteTask>(sortBy: [SortDescriptor(\.sortOrder)])
        )
    }

    @Test func everyTodoBlockBecomesARow() throws {
        let context = try makeContext()
        let document = NoteDocument(title: "Marathon", blocks: [
            NoteBlock(kind: .heading1, text: "Week one"),
            NoteBlock(kind: .todo, text: "Long run", isChecked: true),
            NoteBlock(kind: .paragraph, text: "felt good"),
            NoteBlock(kind: .todo, text: "Buy shoes"),
        ])
        context.insert(document)

        try NoteIndexer.reindex(document, in: context)

        let rows = try tasks(in: context)
        #expect(rows.count == 2)
        #expect(rows.map(\.text) == ["Long run", "Buy shoes"])
        #expect(rows[0].isChecked)
        #expect(rows.allSatisfy { $0.documentID == document.id })
    }

    /// The row keeps the block's identity, so ticking a to-do does not orphan
    /// whatever was attached to it.
    @Test func aRowKeepsItsBlockIdentity() throws {
        let context = try makeContext()
        let block = NoteBlock(kind: .todo, text: "Pack")
        let document = NoteDocument(blocks: [block])
        context.insert(document)

        try NoteIndexer.reindex(document, in: context)

        #expect(try tasks(in: context).first?.id == block.id)
    }

    @Test func theAuthoredDueDateAndGoalCarryDown() throws {
        let context = try makeContext()
        let goal = UUID()
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let document = NoteDocument(blocks: [
            NoteBlock(kind: .todo, text: "Book the flight", dueDate: due, goalID: goal)
        ])
        context.insert(document)

        try NoteIndexer.reindex(document, in: context)

        let row = try #require(try tasks(in: context).first)
        #expect(row.dueDate == due)
        #expect(row.goalID == goal)
    }

    /// Reindexing is a whole document rewrite, so a to-do deleted from the
    /// page leaves nothing behind.
    @Test func aDeletedTodoLosesItsRow() throws {
        let context = try makeContext()
        let document = NoteDocument(blocks: [
            NoteBlock(kind: .todo, text: "Long run"),
            NoteBlock(kind: .todo, text: "Buy shoes"),
        ])
        context.insert(document)
        try NoteIndexer.reindex(document, in: context)

        document.blocks = [NoteBlock(kind: .todo, text: "Long run")]
        try NoteIndexer.reindex(document, in: context)

        #expect(try tasks(in: context).map(\.text) == ["Long run"])
    }

    /// Running twice over unchanged blocks must not double the rows. This is
    /// the property that lets `touch` call it on every keystroke.
    @Test func reindexingTwiceChangesNothing() throws {
        let context = try makeContext()
        let document = NoteDocument(blocks: [NoteBlock(kind: .todo, text: "Pack")])
        context.insert(document)

        try NoteIndexer.reindex(document, in: context)
        try NoteIndexer.reindex(document, in: context)

        #expect(try tasks(in: context).count == 1)
    }

    /// Two pages can hold the same block id, because copy and paste keeps it.
    /// Rows are scoped by document, so both survive.
    @Test func twoPagesMayShareABlockIdentity() throws {
        let context = try makeContext()
        let block = NoteBlock(kind: .todo, text: "Pack")
        let first = NoteDocument(title: "Trip", blocks: [block])
        let second = NoteDocument(title: "Copy", blocks: [block])
        context.insert(first)
        context.insert(second)

        try NoteIndexer.reindex(first, in: context)
        try NoteIndexer.reindex(second, in: context)

        #expect(try tasks(in: context).count == 2)
    }

    /// A tombstoned page is gone as far as every list is concerned, so its
    /// to-dos must not keep showing up in one.
    @Test func aDeletedPageKeepsNoRows() throws {
        let context = try makeContext()
        let document = NoteDocument(blocks: [NoteBlock(kind: .todo, text: "Pack")])
        context.insert(document)
        try NoteIndexer.reindex(document, in: context)

        document.deletedAt = .now
        try NoteIndexer.reindex(document, in: context)

        #expect(try tasks(in: context).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NoteIndexerTests`
Expected: FAIL to compile, with "cannot find 'NoteIndexer' in scope".

- [ ] **Step 3: Write the indexer**

Create `LifeOSKit/Sources/Persistence/NoteIndexer.swift`:

```swift
import Foundation
import SwiftData

/// Mirrors a document's blocks into the derived rows.
///
/// The only writer of `NoteTask` and `NoteLink`. One writer is what makes the
/// index trustworthy: there is exactly one place that can be wrong, and one
/// function that repairs it.
///
/// Never saves. It runs inside the transaction of whatever is already changing
/// the document, so a page and its index cannot be half written with respect
/// to each other.
@MainActor
public enum NoteIndexer {

    /// Rewrites one document's rows from its blocks.
    ///
    /// Delete and reinsert rather than diff. A document holds tens of blocks,
    /// so the rewrite is cheap, and a diff would need its own correctness
    /// argument for every field. A tombstoned page is left with no rows at
    /// all, since nothing should list the to-dos of a deleted page.
    public static func reindex(_ document: NoteDocument, in context: ModelContext) throws {
        let documentID = document.id
        try context.delete(
            model: NoteTask.self,
            where: #Predicate { $0.documentID == documentID }
        )

        guard document.deletedAt == nil else { return }

        for (offset, block) in document.blocks.enumerated() where block.kind == .todo {
            context.insert(
                NoteTask(
                    id: block.id,
                    documentID: documentID,
                    text: block.text,
                    isChecked: block.isChecked,
                    indent: block.indent,
                    dueDate: block.dueDate,
                    goalID: block.goalID,
                    sortOrder: offset
                )
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NoteIndexerTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteIndexer.swift LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift
git commit -m "feat(notes): mirror to-do blocks into queryable rows

Delete and reinsert a whole document at a time, so reindexing is
idempotent and a to-do removed from a page leaves nothing behind. Never
saves: it runs inside the caller's transaction."
```

---

### Task 4: The indexer mirrors wiki links

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteIndexer.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift`

**Interfaces:**
- Consumes: `NoteIndexer.reindex` from Task 3, `NoteLinkScanner.links(in:)` from `NoteBlock.swift`.
- Produces: `NoteLink` rows written by the same `reindex` call. No new public function.

- [ ] **Step 1: Write the failing test**

Add to `NoteIndexerTests`:

```swift
    private func links(in context: ModelContext) throws -> [NoteLink] {
        try context.fetch(FetchDescriptor<NoteLink>())
    }

    @Test func everyWikiLinkBecomesAnEdge() throws {
        let context = try makeContext()
        let document = NoteDocument(title: "Trip", blocks: [
            NoteBlock(text: "See [[Marathon]] and [[Kit list]]")
        ])
        context.insert(document)

        try NoteIndexer.reindex(document, in: context)

        let edges = try links(in: context)
        #expect(edges.count == 2)
        #expect(Set(edges.map(\.targetTitleFolded)) == ["marathon", "kit list"])
        #expect(edges.allSatisfy { $0.sourceID == document.id })
    }

    /// An edge points at a page when one exists by that name, so the mindmap
    /// can draw a real node rather than a name.
    @Test func anEdgeResolvesToThePageItNames() throws {
        let context = try makeContext()
        let target = NoteDocument(title: "Marathon")
        let source = NoteDocument(title: "Trip", blocks: [NoteBlock(text: "see [[marathon]]")])
        context.insert(target)
        context.insert(source)

        try NoteIndexer.reindex(source, in: context)

        #expect(try links(in: context).first?.targetID == target.id)
    }

    /// A link written before its page exists is kept unresolved rather than
    /// dropped. It is a note to self, and the mindmap draws it as a stub.
    @Test func anEdgeToNothingIsKeptUnresolved() throws {
        let context = try makeContext()
        let document = NoteDocument(blocks: [NoteBlock(text: "[[Not written yet]]")])
        context.insert(document)

        try NoteIndexer.reindex(document, in: context)

        let edge = try #require(try links(in: context).first)
        #expect(edge.targetTitleFolded == "not written yet")
        #expect(edge.targetID == nil)
    }

    @Test func aRemovedLinkLosesItsEdge() throws {
        let context = try makeContext()
        let document = NoteDocument(blocks: [NoteBlock(text: "[[Marathon]] [[Kit list]]")])
        context.insert(document)
        try NoteIndexer.reindex(document, in: context)

        document.blocks = [NoteBlock(text: "[[Marathon]]")]
        try NoteIndexer.reindex(document, in: context)

        #expect(try links(in: context).map(\.targetTitleFolded) == ["marathon"])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NoteIndexerTests`
Expected: FAIL, `everyWikiLinkBecomesAnEdge` finds 0 edges where 2 were expected.

- [ ] **Step 3: Extend the indexer**

In `reindex`, add the delete alongside the task delete:

```swift
        try context.delete(
            model: NoteLink.self,
            where: #Predicate { $0.sourceID == documentID }
        )
```

And after the to-do loop, before the closing brace:

```swift
        // Resolved by folded title, because that is how a person writes a
        // link: by the name of the page, not its id. Titles are not unique,
        // so first match wins and the tie is stable only by fetch order. That
        // is the same tie the backlinks list already lives with.
        let titles = try titleIndex(in: context)
        for target in NoteLinkScanner.links(in: document.blocks) {
            let folded = target.lowercased()
            context.insert(
                NoteLink(
                    sourceID: documentID,
                    targetTitleFolded: folded,
                    targetID: titles[folded]
                )
            )
        }
```

And add the helper to the enum:

```swift
    /// Live pages by folded title. Built once per reindex rather than fetched
    /// per link, since a page with twenty links would otherwise mean twenty
    /// fetches for one keystroke.
    private static func titleIndex(in context: ModelContext) throws -> [String: UUID] {
        var index: [String: UUID] = [:]
        for document in try context.fetch(FetchDescriptor<NoteDocument>())
        where document.deletedAt == nil {
            let key = document.displayTitle.lowercased()
            if index[key] == nil { index[key] = document.id }
        }
        return index
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NoteIndexerTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteIndexer.swift LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift
git commit -m "feat(notes): mirror wiki links into an edge set

The mindmap needs the whole graph on every pan, which rescanning every
document cannot give it. Unresolved links are kept rather than dropped:
a link written before its page is a note to self."
```

---

### Task 5: Rebuilding the whole index

The repair path, and what phase 1 runs once on an existing library.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteIndexer.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift`

**Interfaces:**
- Consumes: `reindex` from Tasks 3 and 4.
- Produces: `static func rebuildAll(context: ModelContext) throws -> Int`, returning how many documents were indexed, for the log line.

- [ ] **Step 1: Write the failing test**

Add to `NoteIndexerTests`:

```swift
    @Test func rebuildingIndexesEveryPage() throws {
        let context = try makeContext()
        for title in ["One", "Two", "Three"] {
            context.insert(
                NoteDocument(title: title, blocks: [NoteBlock(kind: .todo, text: "do \(title)")])
            )
        }

        let count = try NoteIndexer.rebuildAll(context: context)

        #expect(count == 3)
        #expect(try tasks(in: context).count == 3)
    }

    /// The repair has to be safe to run on an index that is already right,
    /// because that is the state it will usually be run in.
    @Test func rebuildingTwiceLeavesOneRowPerTodo() throws {
        let context = try makeContext()
        context.insert(NoteDocument(blocks: [NoteBlock(kind: .todo, text: "Pack")]))

        _ = try NoteIndexer.rebuildAll(context: context)
        _ = try NoteIndexer.rebuildAll(context: context)

        #expect(try tasks(in: context).count == 1)
    }

    /// Rows left behind by a page that no longer exists are the one thing a
    /// per document reindex cannot clear, so the rebuild has to.
    @Test func rebuildingClearsRowsWhosePageIsGone() throws {
        let context = try makeContext()
        context.insert(NoteTask(id: UUID(), documentID: UUID(), text: "orphan"))
        context.insert(NoteLink(sourceID: UUID(), targetTitleFolded: "orphan"))
        try context.save()

        _ = try NoteIndexer.rebuildAll(context: context)

        #expect(try tasks(in: context).isEmpty)
        #expect(try links(in: context).isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NoteIndexerTests`
Expected: FAIL to compile, with "type 'NoteIndexer' has no member 'rebuildAll'".

- [ ] **Step 3: Write rebuildAll**

Add to `NoteIndexer`:

```swift
    /// Throws the index away and builds it again from the documents.
    ///
    /// The repair for any inconsistency, and what runs once when the index is
    /// introduced. Starting from empty rather than reindexing page by page is
    /// what clears rows whose page has since been deleted: a per document
    /// pass never visits a page that is not there.
    @discardableResult
    public static func rebuildAll(context: ModelContext) throws -> Int {
        try context.delete(model: NoteTask.self)
        try context.delete(model: NoteLink.self)

        let documents = try context.fetch(FetchDescriptor<NoteDocument>())
        for document in documents {
            try reindex(document, in: context)
        }
        try context.save()
        return documents.count
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NoteIndexerTests`
Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteIndexer.swift LifeOSKit/Tests/PersistenceTests/NoteIndexerTests.swift
git commit -m "feat(notes): rebuild the whole index from the documents

The repair path, and what runs once on an existing library. Starts from
empty rather than reindexing page by page, which is the only way to clear
rows whose page has since been deleted."
```

---

### Task 6: The store keeps the index current

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NotesStore.swift:224-262` (`createDocument`), `:347-350` (`delete`), `:407-411` (`touch`)
- Test: `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift`

**Interfaces:**
- Consumes: `NoteIndexer.reindex` from Tasks 3 and 4.
- Produces: no new API. Every existing `NotesStore` mutation now leaves the index correct.

- [ ] **Step 1: Write the failing test**

Add to `NotesStoreTests`:

```swift
    @Test func editingAPageUpdatesItsIndex() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Marathon", bucket: .projects)

        try store.update(document, blocks: [
            NoteBlock(kind: .todo, text: "Long run"),
            NoteBlock(text: "see [[Kit list]]"),
        ])

        #expect(try store.indexedTasks().map(\.text) == ["Long run"])
        #expect(try store.indexedLinks().map(\.targetTitleFolded) == ["kit list"])
    }

    @Test func aNewPageIsIndexedAsItIsCreated() throws {
        let store = try makeStore()
        try store.createDocument(
            title: "Trip",
            bucket: .projects,
            blocks: [NoteBlock(kind: .todo, text: "Pack")]
        )

        #expect(try store.indexedTasks().count == 1)
    }

    @Test func deletingAPageTakesItsIndexWithIt() throws {
        let store = try makeStore()
        let document = try store.createDocument(
            bucket: .projects,
            blocks: [NoteBlock(kind: .todo, text: "Pack")]
        )

        try store.delete(document)

        #expect(try store.indexedTasks().isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NotesStoreTests`
Expected: FAIL to compile, with "value of type 'NotesStore' has no member 'indexedTasks'".

- [ ] **Step 3: Hook the indexer into the store**

In `NotesStore`, change `touch(_ document:)`:

```swift
    private func touch(_ document: NoteDocument) throws {
        document.updatedAt = .now
        // Every document mutation funnels through here, which is exactly why
        // the index is rewritten here and nowhere else. A path that forgot to
        // reindex would show a stale to-do list with no other symptom.
        try NoteIndexer.reindex(document, in: context)
        try context.save()
    }
```

In `createDocument`, replace the trailing `try context.save()` with:

```swift
        try NoteIndexer.reindex(document, in: context)
        try context.save()
```

In `delete(_ document:)`, add before its save or `touch` call:

```swift
        try NoteIndexer.reindex(document, in: context)
```

(`delete` sets `deletedAt`, and `reindex` clears the rows of a tombstoned page, so this needs no special case.)

Add the two read helpers in the Reading section, after `backlinks(to:)`:

```swift
    /// The indexed to-dos, newest page first. What the To-dos chip reads.
    public func indexedTasks(openOnly: Bool = false) throws -> [NoteTask] {
        let rows = try context.fetch(
            FetchDescriptor<NoteTask>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        return openOnly ? rows.filter { !$0.isChecked } : rows
    }

    /// Every link edge. The mindmap's input.
    public func indexedLinks() throws -> [NoteLink] {
        try context.fetch(FetchDescriptor<NoteLink>())
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NotesStoreTests`
Expected: PASS, all existing tests plus the 3 new ones.

- [ ] **Step 5: Run the whole Persistence suite for regressions**

Run: `cd LifeOSKit && swift test --filter PersistenceTests`
Expected: PASS. `touch` is on the path of every note test, so a mistake here shows up broadly.

- [ ] **Step 6: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NotesStore.swift LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift
git commit -m "feat(notes): keep the index current on every store write

touch is the choke point every document mutation already passes through,
so reindexing there means no future caller can forget. A path that forgot
would show a stale list with no other symptom."
```

---

### Task 7: A note knows whether it has been filed

`filedAt` is the whole Inbox concept, and phase 2's stream reads it. It ships here because it is a document field and belongs with the other model work.

**Files:**
- Modify: `LifeOSKit/Sources/Persistence/NoteDocument.swift:95-140` (fields), `LifeOSKit/Sources/Persistence/NotesStore.swift:316-321` (`move`)
- Test: `LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NoteDocument.filedAt: Date?` and `NoteDocument.isInInbox: Bool`. `NotesStore.inbox() throws -> [NoteCardSnapshot]`.

- [ ] **Step 1: Write the failing test**

Add to `NotesStoreTests`:

```swift
    /// Capture first: a note starts unfiled, and stays that way while it is
    /// only being written in. Deciding where it belongs is what files it.
    @Test func aNewPageStartsInTheInbox() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Idea", bucket: .projects)

        #expect(document.isInInbox)
        #expect(try store.inbox().count == 1)
    }

    @Test func editingDoesNotFileAPage() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Idea", bucket: .projects)

        try store.update(document, blocks: [NoteBlock(text: "more thinking")])

        #expect(document.isInInbox)
    }

    @Test func movingAPageFilesIt() throws {
        let store = try makeStore()
        let folder = try store.createFolder(name: "Training", bucket: .areas)
        let document = try store.createDocument(title: "Idea", bucket: .projects)

        try store.move(document, to: .areas, folderID: folder.id)

        #expect(!document.isInInbox)
        #expect(try store.inbox().isEmpty)
    }

    /// Filing is a decision, and a decision is not unmade by a later edit.
    @Test func filingSticksThroughLaterEdits() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Idea", bucket: .projects)
        try store.move(document, to: .areas, folderID: nil)
        let filedAt = document.filedAt

        try store.update(document, blocks: [NoteBlock(text: "more")])

        #expect(document.filedAt == filedAt)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NotesStoreTests`
Expected: FAIL to compile, with "value of type 'NoteDocument' has no member 'isInInbox'".

- [ ] **Step 3: Add the field and the filing rule**

In `NoteDocument`, after `archivedAt`:

```swift
    /// When someone decided where this page belongs. Nil means it is still in
    /// the Inbox.
    ///
    /// The whole Inbox is this one field. A bucket cannot answer the question,
    /// because every page has a bucket from the moment it is created, whether
    /// or not anyone chose it. Stamped by filing, never by editing, so a page
    /// you keep writing in stays in the Inbox until you decide otherwise.
    public var filedAt: Date?
```

And the accessor, next to `isArchived`:

```swift
    public var isInInbox: Bool { filedAt == nil && archivedAt == nil }
```

In `NotesStore.move`, stamp it:

```swift
    public func move(_ document: NoteDocument, to bucket: NoteBucket, folderID: UUID?) throws {
        document.bucket = bucket
        document.folderID = folderID
        // Choosing a home is what files a page. Editing one never does.
        if document.filedAt == nil { document.filedAt = .now }
        try touch(document)
    }
```

Add the read, after `indexedLinks()`:

```swift
    /// Captured and not yet filed, newest first. The phone's first screen.
    ///
    /// Newest first rather than `displayOrder`: the Inbox is a capture queue,
    /// and the thing you just wrote is the thing you are still thinking about.
    public func inbox() throws -> [NoteCardSnapshot] {
        let names = try folderNames()
        return try documents(includeArchived: false)
            .filter(\.isInInbox)
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { card($0, folderNames: names) }
    }
```

`card(_:folderNames:)` is the existing private helper every other read in this
type goes through (see `recent(limit:)` at `NotesStore.swift:77`). Use it rather
than constructing a `NoteCardSnapshot` by hand, so the Inbox cannot disagree
with the shelf about what a card shows.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NotesStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteDocument.swift LifeOSKit/Sources/Persistence/NotesStore.swift LifeOSKit/Tests/PersistenceTests/NotesStoreTests.swift
git commit -m "feat(notes): let a page be unfiled

One nullable field is the whole Inbox. A bucket cannot answer the
question, since every page has one from birth whether or not anyone chose
it. Stamped by filing, never by editing."
```

---

### Task 8: Existing libraries are indexed and filed once

**Files:**
- Create: `LifeOSKit/Sources/Persistence/NoteIndexMigration.swift`
- Test: `LifeOSKit/Tests/PersistenceTests/NoteIndexMigrationTests.swift`
- Modify: `LIfeOS/App/RootView.swift:600-615` (where `PlanNoteMigration` and note sync are already wired)

**Interfaces:**
- Consumes: `NoteIndexer.rebuildAll` from Task 5, `NoteDocument.filedAt` from Task 7.
- Produces: `@MainActor public enum NoteIndexMigration` with `static func run(context: ModelContext) throws -> Int`.

- [ ] **Step 1: Write the failing test**

Create `LifeOSKit/Tests/PersistenceTests/NoteIndexMigrationTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NoteIndexMigrationTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    /// Everything written before the Inbox existed was filed under the old
    /// model. Leaving it unstamped would greet someone with their whole
    /// library presented as unsorted capture.
    @Test func existingPagesAreTreatedAsFiled() throws {
        let context = try makeContext()
        context.insert(NoteDocument(title: "Marathon", bucket: .projects))
        context.insert(NoteDocument(title: "Reading", bucket: .research))
        try context.save()

        try NoteIndexMigration.run(context: context)

        let documents = try context.fetch(FetchDescriptor<NoteDocument>())
        #expect(documents.allSatisfy { !$0.isInInbox })
    }

    @Test func existingPagesAreIndexed() throws {
        let context = try makeContext()
        context.insert(
            NoteDocument(title: "Marathon", blocks: [NoteBlock(kind: .todo, text: "Long run")])
        )
        try context.save()

        try NoteIndexMigration.run(context: context)

        #expect(try context.fetch(FetchDescriptor<NoteTask>()).count == 1)
    }

    /// Runs on every launch, so it must be safe on every launch. A page
    /// captured after the migration and deliberately left unfiled must not be
    /// filed behind the person's back by the next launch.
    @Test func aLaterCaptureIsNotSweptUpBySecondRun() throws {
        let context = try makeContext()
        context.insert(NoteDocument(title: "Old", bucket: .projects))
        try context.save()
        try NoteIndexMigration.run(context: context)

        let captured = NoteDocument(title: "New idea", bucket: .projects)
        context.insert(captured)
        try context.save()
        try NoteIndexMigration.run(context: context)

        #expect(captured.isInInbox)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NoteIndexMigrationTests`
Expected: FAIL to compile, with "cannot find 'NoteIndexMigration' in scope".

- [ ] **Step 3: Write the migration**

Create `LifeOSKit/Sources/Persistence/NoteIndexMigration.swift`:

```swift
import Foundation
import SwiftData

/// Brings an existing library up to what the index layer assumes, once.
///
/// Two jobs. Every page that predates the Inbox is stamped as filed, because
/// it was filed under the old model and showing someone their entire library
/// as unsorted capture would be a worse first run than any empty state. And
/// the index is built, since no document has ever been through the indexer.
///
/// Idempotent through a marker in `UserDefaults` rather than through the data,
/// because "has this store been stamped" genuinely is a local question: the
/// stamp is a one time interpretation of history, not a fact to sync. A second
/// run must not sweep up pages captured deliberately since.
///
/// The marker is keyed by account. Two people share one device's
/// `UserDefaults` but not their stores, so a single key would let the second
/// account skip its own stamp and meet its whole library in the Inbox.
@MainActor
public enum NoteIndexMigration {
    static func marker(for scope: UserScope) -> String {
        "notes.indexMigration.v1.\(scope.id)"
    }

    @discardableResult
    public static func run(
        context: ModelContext,
        scope: UserScope,
        defaults: UserDefaults = .standard
    ) throws -> Int {
        let key = marker(for: scope)
        if !defaults.bool(forKey: key) {
            let stamp = Date.now
            for document in try context.fetch(FetchDescriptor<NoteDocument>())
            where document.filedAt == nil {
                document.filedAt = stamp
            }
            try context.save()
            defaults.set(true, forKey: key)
        }
        return try NoteIndexer.rebuildAll(context: context)
    }
}
```

The three tests in Step 1 call `run(context:scope:defaults:)`. Give each test its
own scope and its own defaults so runs cannot leak into each other:

```swift
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "notes.migration.\(UUID().uuidString)")!
    }
```

and pass `scope: UserScope(id: "test"), defaults: isolatedDefaults()` at every
call site. In `aLaterCaptureIsNotSweptUpBySecondRun`, hold one `UserDefaults`
in a local and pass the same instance to both runs, since that test is about
the marker surviving between them.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NoteIndexMigrationTests`
Expected: PASS, 3 tests. Pass a fresh `UserDefaults(suiteName:)` per test so runs do not leak into each other.

- [ ] **Step 5: Wire it into launch**

In `RootView`, beside the existing `PlanNoteMigration` call, add:

```swift
                try NoteIndexMigration.run(context: context, scope: scope)
```

using the same `UserScope` the composition root already resolved to open the
store, and the same error handling as the `PlanNoteMigration` call next to it.

- [ ] **Step 6: Build the app to confirm the wiring compiles**

Run: `xcodebuild -project LIfeOS.xcodeproj -scheme LIfeOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Persistence/NoteIndexMigration.swift LifeOSKit/Tests/PersistenceTests/NoteIndexMigrationTests.swift LIfeOS/App/RootView.swift
git commit -m "feat(notes): index and file an existing library once

Pages that predate the Inbox were filed under the old model, so they are
stamped as filed. Showing someone their whole library as unsorted capture
would be a worse first run than any empty state."
```

---

### Task 9: A pull leaves the index correct

**Files:**
- Modify: `LifeOSKit/Sources/Integrations/NoteSync.swift`
- Test: `LifeOSKit/Tests/IntegrationsTests/NoteSyncIndexTests.swift`

**Interfaces:**
- Consumes: `NoteIndexer.reindex` from Tasks 3 and 4.
- Produces: `NoteSync.apply(_ row: NoteDocumentRow, store: NotesStore) throws` changes from `private` to internal so the test can reach it. No public API changes.

The apply path at `NoteSync.swift:191` has three exits, and each needs a
different thing: an existing page updated in place, an existing page tombstoned
and deleted, and a page inserted for the first time. All three are covered below.

- [ ] **Step 1: Make the seam reachable from tests**

At `LifeOSKit/Sources/Integrations/NoteSync.swift:191`, drop `private`:

```swift
    /// Internal rather than private so the index wiring can be tested without
    /// standing up a network. Nothing outside this package calls it.
    func apply(_ row: NoteDocumentRow, store: NotesStore) throws {
```

- [ ] **Step 2: Write the failing test**

Create `LifeOSKit/Tests/IntegrationsTests/NoteSyncIndexTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

@Suite @MainActor struct NoteSyncIndexTests {

    /// `apply` never touches the network, so a REST client pointed at nothing
    /// is enough to exercise it.
    private func makeSync(_ context: ModelContext) -> NoteSync {
        NoteSync(
            context: context,
            rest: SupabaseREST(baseURL: URL(string: "https://example.invalid")!, anonKey: "test"),
            accessToken: { nil }
        )
    }

    private func row(
        id: UUID = UUID(),
        title: String = "Marathon",
        blocks: [NoteBlock] = [NoteBlock(kind: .todo, text: "Long run")],
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) -> NoteDocumentRow {
        NoteDocumentRow(
            id: id, title: title, icon: "", kind: "note",
            bucket: "projects", accent: "sage", folderID: nil,
            blocks: blocks, drawing: nil, entryDate: nil, dueDate: nil,
            status: "todo", sortOrder: 0, isFavorite: false, openedAt: nil,
            archivedAt: nil, createdAt: .now, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }

    /// Derived rows are never pushed, so a document arriving from another
    /// device has no index until this side builds one. Without this, a to-do
    /// written on the phone is invisible in every list on the iPad.
    @Test func aNewlyPulledPageIsIndexed() throws {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let sync = makeSync(context)

        try sync.apply(row(), store: NotesStore(context: context))

        #expect(try context.fetch(FetchDescriptor<NoteTask>()).count == 1)
    }

    @Test func anUpdatedPageIsReindexed() throws {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let sync = makeSync(context)
        let store = NotesStore(context: context)
        let id = UUID()
        try sync.apply(row(id: id, updatedAt: Date(timeIntervalSince1970: 1_000)), store: store)

        try sync.apply(
            row(
                id: id,
                blocks: [
                    NoteBlock(kind: .todo, text: "Long run"),
                    NoteBlock(kind: .todo, text: "Buy shoes"),
                ],
                updatedAt: Date(timeIntervalSince1970: 2_000)
            ),
            store: store
        )

        #expect(try context.fetch(FetchDescriptor<NoteTask>()).count == 2)
    }

    /// A page deleted on another device must take its to-dos out of every
    /// list here, not just disappear from the shelf.
    @Test func aTombstonedPageLosesItsRows() throws {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let sync = makeSync(context)
        let store = NotesStore(context: context)
        let id = UUID()
        try sync.apply(row(id: id, updatedAt: Date(timeIntervalSince1970: 1_000)), store: store)

        try sync.apply(
            row(id: id, updatedAt: Date(timeIntervalSince1970: 2_000), deletedAt: .now),
            store: store
        )

        #expect(try context.fetch(FetchDescriptor<NoteTask>()).isEmpty)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd LifeOSKit && swift test --filter NoteSyncIndexTests`
Expected: FAIL. `aNewlyPulledPageIsIndexed` finds 0 rows where 1 was expected.

- [ ] **Step 4: Reindex at all three exits of apply**

In `apply(_ row: NoteDocumentRow, store:)`:

After `existing.syncedAt = .now`, before that branch's `return`:

```swift
            // Derived rows never travel, so each device builds its own from
            // whatever it just pulled.
            try NoteIndexer.reindex(existing, in: context)
```

In the tombstone branch, before `context.delete(existing)`:

```swift
                // Clear the index before the page goes, since a deleted row
                // cannot be reindexed afterwards.
                existing.deletedAt = row.deletedAt
                try NoteIndexer.reindex(existing, in: context)
```

And at the end of the insert path, after `context.insert(document)`:

```swift
        try NoteIndexer.reindex(document, in: context)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd LifeOSKit && swift test --filter NoteSyncIndexTests`
Expected: PASS.

- [ ] **Step 6: Run the whole suite**

Run: `cd LifeOSKit && swift test`
Expected: PASS, every suite.

- [ ] **Step 7: Commit**

```bash
git add LifeOSKit/Sources/Integrations/NoteSync.swift LifeOSKit/Tests/IntegrationsTests/NoteSyncIndexTests.swift
git commit -m "fix(notes): index pages arriving from the server

Derived rows are never pushed, so each device builds its own. Without
this a to-do written on the phone is invisible in every list on the iPad."
```

---

## Done when

- `swift test` passes from `LifeOSKit/`.
- The app builds and launches, and an existing library shows no notes in the Inbox.
- Editing a page updates its to-do rows and link edges within the same save.
- `NoteIndexer.rebuildAll` restores a correct index from the documents alone.
- Nothing new is pushed to Supabase. `NoteDocumentRow` is unchanged.

## What phase 2 picks up

`NotesStore.inbox()`, `indexedTasks(openOnly:)` and `indexedLinks()` are the three reads the phone shell is built on. Phase 2 builds `NoteInboxScreen` and the composer against them, and does not need to touch persistence again.
