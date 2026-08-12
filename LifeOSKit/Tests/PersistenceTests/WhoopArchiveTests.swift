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

    @Test func batchStoresDistinctRecordsAsSeparateRows() throws {
        let archive = try makeArchive()
        try archive.store([
            (kind: "recovery", externalID: "r-1", payload: Data("r1".utf8)),
            (kind: "recovery", externalID: "r-2", payload: Data("r2".utf8)),
        ])

        #expect(try archive.count() == 2)
        let payloads = try archive.payloads(kind: "recovery").map { String(decoding: $0, as: UTF8.self) }
        #expect(Set(payloads) == Set(["r1", "r2"]))
    }

    /// A page concatenated with a prior page can contain the same key twice in
    /// one call. Only one `save()` happens for the whole batch, so the second
    /// occurrence must be recognized against the first's still-unsaved insert
    /// rather than becoming a duplicate the unique constraint then rejects.
    @Test func batchWithADuplicateKeyWithinItselfKeepsOneRowWithTheLastPayload() throws {
        let archive = try makeArchive()
        try archive.store([
            (kind: "recovery", externalID: "r-1", payload: Data("first".utf8)),
            (kind: "recovery", externalID: "r-1", payload: Data("second".utf8)),
        ])

        #expect(try archive.count() == 1)
        let payloads = try archive.payloads(kind: "recovery")
        #expect(payloads.count == 1)
        #expect(String(decoding: payloads[0], as: UTF8.self) == "second")
    }

    @Test func batchUpdatesAKeyThatAlreadyExistsInTheStoreRatherThanInserting() throws {
        let archive = try makeArchive()
        try archive.store(kind: "recovery", externalID: "r-1", payload: Data("original".utf8))

        try archive.store([
            (kind: "recovery", externalID: "r-1", payload: Data("updated".utf8)),
        ])

        #expect(try archive.count() == 1)
        let payloads = try archive.payloads(kind: "recovery")
        #expect(payloads.count == 1)
        #expect(String(decoding: payloads[0], as: UTF8.self) == "updated")
    }

    /// The body kind has no date of its own in its payload, unlike the other
    /// four kinds. `receivedAt` is the only day a rebuild can attribute it to,
    /// so `records(kind:)` exists as a sibling to `payloads(kind:)` that keeps
    /// that timestamp rather than dropping it.
    @Test func recordsCarryTheirReceivedAtAlongsideThePayload() throws {
        let archive = try makeArchive()
        try archive.store(kind: "body", externalID: "self", payload: Data(#"{"weight_kilogram":90.7}"#.utf8))

        let records = try archive.records(kind: "body")
        #expect(records.count == 1)
        #expect(String(decoding: records[0].payload, as: UTF8.self) == #"{"weight_kilogram":90.7}"#)
        #expect(records[0].receivedAt <= Date())
    }

    /// A re-sync overwrites the one body record in place, and the timestamp it
    /// was received at must move forward with it, the same as the payload does.
    @Test func restoringTheSameRecordUpdatesItsReceivedAtToo() throws {
        let archive = try makeArchive()
        try archive.store(kind: "body", externalID: "self", payload: Data(#"{"weight_kilogram":90.0}"#.utf8))
        let first = try #require(try archive.records(kind: "body").first)

        try archive.store(kind: "body", externalID: "self", payload: Data(#"{"weight_kilogram":91.0}"#.utf8))
        let second = try #require(try archive.records(kind: "body").first)

        #expect(second.receivedAt > first.receivedAt)
        #expect(String(decoding: second.payload, as: UTF8.self) == #"{"weight_kilogram":91.0}"#)
    }
}

/// Every added property must be optional. SwiftData's implicit lightweight
/// migration covers additive-and-optional only, and a non-optional addition
/// produces a store that will not open on an existing install.
@Suite @MainActor struct WidenedModelTests {
    @Test func theContainerStillOpensWithTheWidenedSchema() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        // The `try` above is the real assertion: a non-optional addition makes
        // the store fail to open. This names the entity so the test also fails
        // if the model is dropped from the schema rather than merely widened.
        let names = container.schema.entities.map(\.name)
        #expect(names.contains("WhoopRawRecord"))
        #expect(names.contains("DailyMetrics"))
    }

    @Test func newDailyMetricsFieldsDefaultToNilRatherThanZero() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MetricsStore(context: ModelContext(container))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

        try store.upsert(date: day) { $0.steps = 100 }
        let row = try #require(try store.metrics(from: day, to: day).first)

        #expect(row.spo2Percentage == nil)
        #expect(row.skinTempCelsius == nil)
        #expect(row.respiratoryRate == nil)
        #expect(row.whoopCalories == nil)
    }

    @Test func sleepRecordCarriesItsStages() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let record = SleepRecord(externalID: "s-1", start: .now, end: .now.addingTimeInterval(3600),
                                 attributedDate: Calendar.current.startOfDay(for: .now))
        record.lightMinutes = 200
        record.remMinutes = 90
        record.swsMinutes = 80
        context.insert(record)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<SleepRecord>()).first)
        #expect(stored.lightMinutes == 200)
        #expect(stored.remMinutes == 90)
        #expect(stored.swsMinutes == 80)
        #expect(stored.respiratoryRate == nil)
    }

    @Test func workoutRecordCarriesStrainAndHeartRates() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let workout = WorkoutRecord(externalID: "w-1", start: .now, durationMinutes: 45,
                                    activityName: "Running", energyKcal: 500)
        workout.strain = 12.4
        workout.averageHR = 145
        workout.maxHR = 178
        context.insert(workout)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<WorkoutRecord>()).first)
        #expect(stored.strain == 12.4)
        #expect(stored.averageHR == 145)
        #expect(stored.distanceMeters == nil)
    }
}
