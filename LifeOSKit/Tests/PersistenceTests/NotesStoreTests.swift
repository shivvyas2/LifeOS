import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NotesStoreTests {
    private func makeStore() throws -> NotesStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return NotesStore(context: ModelContext(container))
    }

    @Test func librarySnapshotsKeepCreationEditAndOpenDatesSeparate() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Reading", bucket: .projects)
        let created = Date(timeIntervalSince1970: 100)
        let edited = Date(timeIntervalSince1970: 200)
        let opened = Date(timeIntervalSince1970: 300)
        page.createdAt = created
        page.updatedAt = edited
        page.openedAt = opened
        let card = try #require(store.cards(bucket: .projects).first)
        #expect(card.createdAt == created)
        #expect(card.updatedAt == edited)
        #expect(card.openedAt == opened)
    }

    @Test func aNewPageLandsOnTheShelfItWasMadeOn() throws {
        let store = try makeStore()
        try store.createDocument(title: "Marathon", bucket: .projects)

        #expect(try store.cards(bucket: .projects).count == 1)
        #expect(try store.cards(bucket: .research).isEmpty)
    }

    @Test func aPageInheritsItsFoldersColour() throws {
        let store = try makeStore()
        let folder = try store.createFolder(name: "Training", bucket: .projects)
        try store.setAccent(.clay, on: folder)

        let document = try store.createDocument(bucket: .projects, folderID: folder.id)

        #expect(document.accent == .clay)
    }

    /// A parent row in the rail shows what is under it, not just what is
    /// filed directly on it.
    @Test func folderCountsRollUpThroughChildren() throws {
        let store = try makeStore()
        let parent = try store.createFolder(name: "Health", bucket: .areas)
        let child = try store.createFolder(name: "Running", bucket: .areas, parentID: parent.id)
        try store.createDocument(bucket: .areas, folderID: parent.id)
        try store.createDocument(bucket: .areas, folderID: child.id)
        try store.createDocument(bucket: .areas, folderID: child.id)

        let snapshot = try store.snapshot()
        let health = snapshot.folders(in: .areas).first { $0.name == "Health" }

        #expect(health?.count == 3)
        #expect(health?.children.first?.count == 2)
    }

    @Test func archivingMovesAPageToTheArchiveShelfAndOffItsOwn() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Old project", bucket: .projects)

        try store.archive(document)

        #expect(try store.cards(bucket: .projects).isEmpty)
        #expect(try store.cards(bucket: .archive).count == 1)
    }

    /// Restoring must need no filing decision, which only works if the page
    /// kept the shelf it came from the whole time it was archived.
    @Test func restoringReturnsAPageToTheShelfItCameFrom() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Reading", bucket: .research)

        try store.archive(document)
        try store.unarchive(document)

        #expect(try store.cards(bucket: .research).count == 1)
        #expect(try store.cards(bucket: .archive).isEmpty)
    }

    @Test func deletingAFolderKeepsThePagesThatWereInIt() throws {
        let store = try makeStore()
        let folder = try store.createFolder(name: "Scratch", bucket: .projects)
        try store.createDocument(title: "Kept", bucket: .projects, folderID: folder.id)

        try store.delete(folder)

        let remaining = try store.cards(bucket: .projects)
        #expect(remaining.count == 1)
        #expect(remaining.first?.folderID == nil)
    }

    @Test func deletingAFolderRehomesItsChildrenRatherThanOrphaningThem() throws {
        let store = try makeStore()
        let parent = try store.createFolder(name: "Parent", bucket: .areas)
        let middle = try store.createFolder(name: "Middle", bucket: .areas, parentID: parent.id)
        let leaf = try store.createFolder(name: "Leaf", bucket: .areas, parentID: middle.id)

        try store.delete(middle)

        #expect(try store.folder(id: leaf.id)?.parentID == parent.id)
    }

    /// A delete has to survive as a fact long enough to reach the server, or
    /// the next pull hands the page straight back.
    @Test func deletingAPageLeavesATombstoneUntilItIsPushed() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Gone", bucket: .projects)
        let id = document.id

        try store.delete(document)

        #expect(try store.cards(bucket: .projects).isEmpty)
        #expect(try store.pendingDocuments().contains { $0.id == id })

        try store.markSynced(documentIDs: [id], folderIDs: [])
        #expect(try store.pendingDocuments().isEmpty)
    }

    @Test func onlyChangedRowsArePending() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Note", bucket: .projects)

        #expect(try store.pendingDocuments().count == 1)
        try store.markSynced(documentIDs: [document.id], folderIDs: [])
        #expect(try store.pendingDocuments().isEmpty)

        try store.rename(document, to: "Renamed")
        #expect(try store.pendingDocuments().count == 1)
    }

    /// Reading a page on one device must not fabricate an edit that beats a
    /// real edit made on another.
    @Test func openingAPageDoesNotMarkItDirty() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Note", bucket: .projects)
        try store.markSynced(documentIDs: [document.id], folderIDs: [])

        try store.markOpened(document)

        #expect(try store.pendingDocuments().isEmpty)
    }

    @Test func todaysJournalIsCreatedOnceAndThenReused() throws {
        let store = try makeStore()
        let first = try store.journalEntry()
        let second = try store.journalEntry()

        #expect(first.id == second.id)
        #expect(first.kind == .journal)
        #expect(first.entryDate != nil)
    }

    @Test func backlinksFindThePagesThatPointHere() throws {
        let store = try makeStore()
        try store.createDocument(title: "Marathon", bucket: .projects)
        try store.createDocument(
            title: "Tuesday",
            bucket: .areas,
            blocks: [NoteBlock(text: "Session for [[Marathon]] block")]
        )

        let links = try store.backlinks(to: "Marathon")

        #expect(links.count == 1)
        #expect(links.first?.title == "Tuesday")
        #expect(links.first?.context.contains("[[Marathon]]") == true)
    }

    /// Obsidian matches links case insensitively and so must this, or a link
    /// typed in a hurry silently points at nothing.
    @Test func backlinksIgnoreCase() throws {
        let store = try makeStore()
        try store.createDocument(title: "Marathon", bucket: .projects)
        try store.createDocument(bucket: .areas, blocks: [NoteBlock(text: "see [[marathon]]")])

        #expect(try store.backlinks(to: "Marathon").count == 1)
    }

    @Test func searchLooksInsideTheBodyNotJustTheTitle() throws {
        let store = try makeStore()
        try store.createDocument(
            title: "Tuesday",
            bucket: .areas,
            blocks: [NoteBlock(text: "calf felt tight on the hills")]
        )

        #expect(try store.search("hills").count == 1)
        #expect(try store.search("Tuesday").count == 1)
        #expect(try store.search("swimming").isEmpty)
    }

    @Test func searchReachesArchivedPages() throws {
        let store = try makeStore()
        let document = try store.createDocument(title: "Buried", bucket: .projects)
        try store.archive(document)

        #expect(try store.search("Buried").count == 1)
    }

    @Test func anUntitledPageIsNamedByItsFirstLine() throws {
        let store = try makeStore()
        let document = try store.createDocument(
            bucket: .projects,
            blocks: [NoteBlock(text: "First thing I wrote")]
        )

        #expect(document.displayTitle == "First thing I wrote")
    }

    @Test func favouritesLeadTheShelf() throws {
        let store = try makeStore()
        try store.createDocument(title: "Ordinary", bucket: .projects)
        let starred = try store.createDocument(title: "Starred", bucket: .projects)
        try store.toggleFavorite(starred)

        #expect(try store.cards(bucket: .projects).first?.title == "Starred")
    }

    @Test func aShelfCanBeNarrowedToOneFolderOrToItsLoosePages() throws {
        let store = try makeStore()
        let folder = try store.createFolder(name: "Training", bucket: .projects)
        try store.createDocument(title: "In folder", bucket: .projects, folderID: folder.id)
        try store.createDocument(title: "Loose", bucket: .projects)

        #expect(try store.cards(bucket: .projects).count == 2)
        #expect(try store.cards(bucket: .projects, folder: .some(folder.id)).count == 1)
        #expect(try store.cards(bucket: .projects, folder: .some(nil)).first?.title == "Loose")
    }

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

    /// Deleting a folder moves every page it held, which is a document
    /// mutation that does not go through `touch`. Without a reindex there, the
    /// rows keep the old `documentUpdatedAt` and every cross page list orders
    /// those pages as though they had not been touched for years.
    @Test func emptyingAFolderKeepsTheIndexCurrent() throws {
        let store = try makeStore()
        let folder = try store.createFolder(name: "Scratch", bucket: .projects)
        let document = try store.createDocument(
            title: "Kit list",
            bucket: .projects,
            folderID: folder.id,
            blocks: [NoteBlock(kind: .todo, text: "Pack")]
        )

        try store.delete(folder)

        let row = try #require(try store.indexedTasks().first)
        #expect(row.documentUpdatedAt == document.updatedAt)
    }

    /// Ordering across pages comes from the page, not from the block offset.
    /// Sorting by sortOrder alone interleaved every page's first to-do, which
    /// is what this guards against.
    @Test func todosAcrossPagesAreNewestPageFirst() throws {
        let store = try makeStore()
        let older = try store.createDocument(title: "Older", bucket: .projects)
        try store.update(older, blocks: [
            NoteBlock(kind: .todo, text: "older first"),
            NoteBlock(kind: .todo, text: "older second"),
        ])
        let newer = try store.createDocument(title: "Newer", bucket: .projects)
        try store.update(newer, blocks: [NoteBlock(kind: .todo, text: "newer first")])

        #expect(try store.indexedTasks().map(\.text)
                == ["newer first", "older first", "older second"])
    }

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

    @Test func taskGroupsListOpenToDosUnderTheirPagesNewestFirst() throws {
        let store = try makeStore()
        let groceries = try store.createDocument(title: "Groceries", bucket: .projects, blocks: [
            NoteBlock(kind: .todo, text: "Buy oat milk"),
            NoteBlock(kind: .todo, text: "Done already", isChecked: true),
            NoteBlock(kind: .todo, text: "Order the filter"),
        ])
        let marathon = try store.createDocument(title: "Marathon", bucket: .areas, blocks: [
            NoteBlock(kind: .todo, text: "Book the physio"),
        ])
        let gone = try store.createDocument(title: "Gone", bucket: .research, blocks: [
            NoteBlock(kind: .todo, text: "Never shown"),
        ])
        try store.archive(gone)

        let groups = try store.taskGroups()

        #expect(groups.map(\.page.id) == [marathon.id, groceries.id])
        #expect(groups[1].rows.map(\.text) == ["Buy oat milk", "Order the filter"])
        #expect(groups[1].rows.map(\.isDone) == [false, false])
        if case .page(let documentID, let blockID) = groups[0].rows[0].source {
            #expect(documentID == marathon.id)
            #expect(blockID == marathon.blocks[0].id)
        } else {
            Issue.record("a To-dos row must point at its page and block")
        }
        let allEditable = groups.flatMap(\.rows).allSatisfy(\.isEditable)
        #expect(allEditable)
    }

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
}
