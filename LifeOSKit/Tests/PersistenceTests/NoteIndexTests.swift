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
