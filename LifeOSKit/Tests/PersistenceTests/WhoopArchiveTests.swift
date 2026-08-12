import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct WhoopArchiveTests {
    private func makeArchive() throws -> WhoopArchive {
        let container = try LifeOSContainer.make(inMemory: true)
        return WhoopArchive(context: ModelContext(container))
    }

    @Test func storingAPayloadMakesItReadableBack() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data(#"{"a":1}"#.utf8))

        let payloads = try archive.payloads(kind: "recovery")
        #expect(payloads.count == 1)
        #expect(String(decoding: payloads[0], as: UTF8.self) == #"{"a":1}"#)
    }

    /// A re-sync sees the same records again. Storing them must correct the row
    /// rather than pile up a duplicate for every sync the user ever runs.
    @Test func restoringTheSameRecordUpdatesRatherThanDuplicating() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data(#"{"v":1}"#.utf8))
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data(#"{"v":2}"#.utf8))

        let payloads = try archive.payloads(kind: "recovery")
        #expect(payloads.count == 1)
        #expect(String(decoding: payloads[0], as: UTF8.self) == #"{"v":2}"#)
    }

    /// The same external id in two collections is two different records.
    @Test func kindIsPartOfIdentity() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "1", payload: Data("r".utf8))
        try archive.store(kind: "cycle", externalID: "1", payload: Data("c".utf8))

        #expect(try archive.payloads(kind: "recovery").count == 1)
        #expect(try archive.payloads(kind: "cycle").count == 1)
        #expect(try archive.count() == 2)
    }

    @Test func readingAnEmptyKindReturnsNothingRatherThanFailing() throws {
        let archive = try makeArchive()
        #expect(try archive.payloads(kind: "workout").isEmpty)
    }
}
