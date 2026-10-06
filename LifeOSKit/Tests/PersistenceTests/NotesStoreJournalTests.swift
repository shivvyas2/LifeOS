import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NotesStoreJournalTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func makeStore() throws -> NotesStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return NotesStore(context: ModelContext(container), calendar: calendar)
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9))! }

    @Test func readingADayCreatesNothing() throws {
        let store = try makeStore()
        #expect(try store.journalEntryIfPresent(on: day) == nil)
        #expect(try store.documents(includeArchived: true).isEmpty)
        let page = try store.journalEntry(on: day)
        #expect(try store.journalEntryIfPresent(on: day)?.id == page.id)
        #expect(try store.journalEntryIfPresent(on: day.addingTimeInterval(86_400)) == nil)
    }

    @Test func aJournalPageLandsInTheJournalFolderAndMakesItWhenMissing() throws {
        let store = try makeStore()
        let page = try store.journalEntry(on: day)
        let folder = try #require(try store.folders().first { $0.name == "Journal" })
        #expect(folder.bucket == .areas)
        #expect(page.folderID == folder.id)
        #expect(page.filedAt != nil)
        let second = try store.journalEntry(on: day.addingTimeInterval(86_400))
        #expect(second.folderID == folder.id)
        #expect(try store.folders().filter { $0.name == "Journal" }.count == 1)
    }

    @Test func tasksDueOnADaySpanTheWholeDay() throws {
        let store = try makeStore()
        let page = try store.createDocument(title: "Groceries", bucket: .projects)
        try store.update(page, blocks: [
            NoteBlock(kind: .todo, text: "Morning", dueDate: calendar.startOfDay(for: day)),
            NoteBlock(kind: .todo, text: "Evening", dueDate: day.addingTimeInterval(13 * 3_600)),
            NoteBlock(kind: .todo, text: "Tomorrow", dueDate: day.addingTimeInterval(86_400)),
            NoteBlock(kind: .todo, text: "Undated"),
        ])
        #expect(try store.tasks(dueOn: day).map(\.text) == ["Morning", "Evening"])
    }
}
