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
}
