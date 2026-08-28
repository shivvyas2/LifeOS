import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NoteStreamTests {
    private func makeStore() throws -> NotesStore {
        NotesStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    @Test func theChipRowReadsInboxAllToDos() {
        #expect(NoteStreamChip.rowOrder == [.inbox, .all, .todos])
        #expect(NoteStreamChip.inbox.title == "Inbox")
        #expect(NoteStreamChip.all.title == "All")
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
        let task = try #require(try store.capture("Gone too", isTodo: true))
        try store.archive(captured)
        try store.archive(task)

        guard case .cards(let inbox) = try store.stream(for: .inbox),
              case .cards(let all) = try store.stream(for: .all),
              case .tasks(let todos) = try store.stream(for: .todos) else {
            Issue.record("unexpected stream shapes")
            return
        }
        #expect(inbox.isEmpty)
        #expect(all.isEmpty)
        #expect(todos.isEmpty)
    }

    /// The filter must remove archived pages' to-dos and nothing else.
    @Test func aLivePageKeepsItsToDosInTheChip() throws {
        let store = try makeStore()
        let live = try #require(try store.capture("Still here", isTodo: true))
        let archived = try #require(try store.capture("Gone", isTodo: true))
        try store.archive(archived)

        guard case .tasks(let todos) = try store.stream(for: .todos) else {
            Issue.record("todos should be tasks")
            return
        }
        #expect(todos.map(\.documentID) == [live.id])
    }

    @Test func anEmptyStreamSaysSoWhicheverShapeItIs() {
        #expect(NoteStream.cards([]).isEmpty)
        #expect(NoteStream.tasks([]).isEmpty)
    }
}
