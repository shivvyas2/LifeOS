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

    /// A page made on another device was filed there. Arriving here it is not
    /// new capture, and a fresh install pulling a whole library must not meet
    /// all of it as an Inbox to sort.
    @Test func aPulledPageIsNotInTheInbox() throws {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let sync = makeSync(context)

        try sync.apply(row(), store: NotesStore(context: context))

        let pulled = try #require(try context.fetch(FetchDescriptor<NoteDocument>()).first)
        #expect(!pulled.isInInbox)
    }
}
