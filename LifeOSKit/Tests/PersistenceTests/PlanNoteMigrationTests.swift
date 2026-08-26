import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct PlanNoteMigrationTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    @Test func goalsAndNotesAndJournalsBecomePages() throws {
        let context = try makeContext()
        let plan = PlanStore(context: context)
        try plan.add(kind: .goal, title: "Run a marathon")
        try plan.add(kind: .note, title: "Shoe research")
        try plan.add(kind: .journal, title: "Slept badly, ran anyway")

        let created = try PlanNoteMigration.run(context: context)

        #expect(created == 3)
        let store = NotesStore(context: context)
        #expect(try store.cards(bucket: .projects).count == 1)
        #expect(try store.cards(bucket: .research).count == 1)
        #expect(try store.cards(bucket: .areas).count == 1)
    }

    /// A habit is a daily tick with a streak behind it and Today toggles those
    /// ticks live. Turning one into a document would leave two rows claiming to
    /// be the same habit.
    @Test func habitsAreLeftAlone() throws {
        let context = try makeContext()
        try PlanStore(context: context).add(kind: .habit, title: "Meditate")

        #expect(try PlanNoteMigration.run(context: context) == 0)
        #expect(try PlanStore(context: context).entries(kind: .habit).count == 1)
    }

    @Test func runningTwiceDoesNotDuplicateAnything() throws {
        let context = try makeContext()
        try PlanStore(context: context).add(kind: .goal, title: "Run a marathon")

        #expect(try PlanNoteMigration.run(context: context) == 1)
        #expect(try PlanNoteMigration.run(context: context) == 0)
        #expect(try NotesStore(context: context).documents(includeArchived: true).count == 1)
    }

    /// A journal entry had no title: its whole text lived in the title field.
    /// Migrating that as a title would produce a page whose heading is a
    /// paragraph.
    @Test func aJournalEntrysTextBecomesItsBodyAndTheDayBecomesItsTitle() throws {
        let context = try makeContext()
        try PlanStore(context: context).add(kind: .journal, title: "Rained the whole way round")

        try PlanNoteMigration.run(context: context)

        let page = try #require(
            try NotesStore(context: context).documents(includeArchived: true).first
        )
        #expect(page.kind == .journal)
        #expect(page.entryDate != nil)
        #expect(page.blocks.contains { $0.text == "Rained the whole way round" })
        #expect(page.title != "Rained the whole way round")
    }

    @Test func aGoalsDetailBecomesItsBlocksAndItsStatusSurvives() throws {
        let context = try makeContext()
        try PlanStore(context: context).add(
            kind: .goal, title: "Ship the app", detail: "- [x] Beta\n- [ ] Review", status: .inProgress
        )

        try PlanNoteMigration.run(context: context)

        let page = try #require(
            try NotesStore(context: context).documents(includeArchived: true).first
        )
        #expect(page.status == .inProgress)
        #expect(NoteBlockParser.taskProgress(page.blocks) == (done: 1, total: 2))
    }

    @Test func foldersAreOnlyMadeForKindsThatHaveSomethingInThem() throws {
        let context = try makeContext()
        try PlanStore(context: context).add(kind: .note, title: "Just a note")

        try PlanNoteMigration.run(context: context)

        let folders = try NotesStore(context: context).folders()
        #expect(folders.count == 1)
        #expect(folders.first?.bucket == .research)
    }

    @Test func aFreshInstallGetsSomewhereToJournalAndNothingElse() throws {
        let context = try makeContext()

        try PlanNoteMigration.seedIfEmpty(context: context)

        let folders = try NotesStore(context: context).folders()
        #expect(folders.map(\.name) == ["Journal"])
        #expect(folders.first?.bucket == .areas)
    }

    @Test func seedingDoesNothingWhenThereIsAlreadyATree() throws {
        let context = try makeContext()
        let store = NotesStore(context: context)
        try store.createFolder(name: "Mine", bucket: .projects)

        try PlanNoteMigration.seedIfEmpty(context: context)

        #expect(try store.folders().count == 1)
    }
}
