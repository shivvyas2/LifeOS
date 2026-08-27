import Testing
import Foundation
import SwiftData
@testable import Persistence

/// Provenance rides alongside the values, keyed the same way the extras bag is.
@Suite @MainActor struct DailyMetricsSourcesTests {

    private func row() throws -> DailyMetrics {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let row = DailyMetrics(date: Calendar.current.startOfDay(for: .now))
        context.insert(row)
        return row
    }

    @Test func aRowStartsWithNoProvenance() throws {
        let row = try row()
        #expect(row.sourcesData == nil)
        #expect(row.sources.isEmpty)
        #expect(row.source("steps") == nil)
    }

    @Test func aSourceRoundTripsThroughTheBag() throws {
        let row = try row()
        row.setSource("steps", "appleHealth")
        row.setSource("hrvMs", "whoop")

        #expect(row.source("steps") == "appleHealth")
        #expect(row.source("hrvMs") == "whoop")
        #expect(row.sources.count == 2)
    }

    /// Clearing removes the key rather than storing an empty string, so an
    /// absent attribution stays absent rather than becoming a source named "".
    @Test func clearingASourceRemovesTheKey() throws {
        let row = try row()
        row.setSource("steps", "appleHealth")
        row.setSource("steps", nil)

        #expect(row.source("steps") == nil)
        #expect(row.sources.isEmpty)
        #expect(row.sourcesData == nil)
    }

    /// Unreadable bytes must not take the row down with them. A day whose
    /// provenance cannot be decoded still has its numbers, and losing the
    /// screen over the attribution would be the worse failure.
    @Test func unreadableProvenanceReadsAsEmptyRatherThanThrowing() throws {
        let row = try row()
        row.sourcesData = Data([0x00, 0x01, 0x02])
        #expect(row.sources.isEmpty)
        #expect(row.source("steps") == nil)
    }
}
