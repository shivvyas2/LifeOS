import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct NoteIndexMigrationTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    /// Each test gets its own suite so a run cannot leak into another test or
    /// into the real per-account defaults on this machine.
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "notes.migration.\(UUID().uuidString)")!
    }

    /// Everything written before the Inbox existed was filed under the old
    /// model. Leaving it unstamped would greet someone with their whole
    /// library presented as unsorted capture.
    @Test func existingPagesAreTreatedAsFiled() throws {
        let context = try makeContext()
        context.insert(NoteDocument(title: "Marathon", bucket: .projects))
        context.insert(NoteDocument(title: "Reading", bucket: .research))
        try context.save()

        try NoteIndexMigration.run(context: context, defaults: isolatedDefaults())

        let documents = try context.fetch(FetchDescriptor<NoteDocument>())
        #expect(documents.allSatisfy { !$0.isInInbox })
    }

    @Test func existingPagesAreIndexed() throws {
        let context = try makeContext()
        context.insert(
            NoteDocument(title: "Marathon", blocks: [NoteBlock(kind: .todo, text: "Long run")])
        )
        try context.save()

        try NoteIndexMigration.run(context: context, defaults: isolatedDefaults())

        #expect(try context.fetch(FetchDescriptor<NoteTask>()).count == 1)
    }

    /// Runs on every launch, so it must be safe on every launch. A page
    /// captured after the migration and deliberately left unfiled must not be
    /// filed behind the person's back by the next launch.
    @Test func aLaterCaptureIsNotSweptUpBySecondRun() throws {
        let context = try makeContext()
        let defaults = isolatedDefaults()
        context.insert(NoteDocument(title: "Old", bucket: .projects))
        try context.save()
        try NoteIndexMigration.run(context: context, defaults: defaults)

        let captured = NoteDocument(title: "New idea", bucket: .projects)
        context.insert(captured)
        try context.save()
        try NoteIndexMigration.run(context: context, defaults: defaults)

        #expect(captured.isInInbox)
    }

    /// A fresh install runs this before its first pull, so there is nothing to
    /// stamp and no history to interpret. Spending the one-shot there would
    /// leave the whole pulled library sitting in the Inbox.
    @Test func anEmptyStoreDoesNotSpendTheOneShot() throws {
        let context = try makeContext()
        let defaults = isolatedDefaults()

        try NoteIndexMigration.run(context: context, defaults: defaults)

        let pulled = NoteDocument(title: "Marathon", bucket: .projects)
        context.insert(pulled)
        try context.save()
        try NoteIndexMigration.run(context: context, defaults: defaults)

        #expect(!pulled.isInInbox)
    }
}
