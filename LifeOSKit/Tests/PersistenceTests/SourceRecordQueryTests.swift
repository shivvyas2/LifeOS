import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct SourceRecordQueryTests {
    private func makeStore() throws -> MetricsStore {
        MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: - Workouts

    @Test func workoutsAreScopedToTheirDay() throws {
        let store = try MetricsStore(context: ModelContext(LifeOSContainer.make(inMemory: true)),
                                     calendar: calendar)
        try store.upsertWorkoutRecord(externalID: "a", start: date(2026, 8, 10, 6),
                                      durationMinutes: 52, activityName: "running") { _ in }
        try store.upsertWorkoutRecord(externalID: "b", start: date(2026, 8, 11, 6),
                                      durationMinutes: 41, activityName: "lifting") { _ in }

        #expect(try store.workouts(on: date(2026, 8, 10)).map(\.activityName) == ["running"])
        #expect(try store.workouts(on: date(2026, 8, 11)).map(\.activityName) == ["lifting"])
        #expect(try store.workouts(on: date(2026, 8, 12)).isEmpty)
    }

    /// A day's sessions read in the order they happened, which is how a list of
    /// them is read.
    @Test func aDaysWorkoutsComeBackOldestFirst() throws {
        let store = try MetricsStore(context: ModelContext(LifeOSContainer.make(inMemory: true)),
                                     calendar: calendar)
        try store.upsertWorkoutRecord(externalID: "pm", start: date(2026, 8, 10, 18),
                                      durationMinutes: 41, activityName: "lifting") { _ in }
        try store.upsertWorkoutRecord(externalID: "am", start: date(2026, 8, 10, 6),
                                      durationMinutes: 52, activityName: "running") { _ in }

        #expect(try store.workouts(on: date(2026, 8, 10)).map(\.activityName)
                == ["running", "lifting"])
    }

    // MARK: - Sleep records

    @Test func sleepRecordsComeBackForTheWindowOldestFirst() throws {
        let store = try MetricsStore(context: ModelContext(LifeOSContainer.make(inMemory: true)),
                                     calendar: calendar)
        for day in 9...12 {
            try store.upsertSleepRecord(
                externalID: "n\(day)", start: date(2026, 8, day - 1, 23),
                end: date(2026, 8, day, 7), attributedDate: date(2026, 8, day)
            ) { $0.lightMinutes = day }
        }

        let window = try store.sleepRecords(from: date(2026, 8, 10), to: date(2026, 8, 11))
        #expect(window.map(\.lightMinutes) == [10, 11])
    }

    /// Naps are stored but are not nights. A composition chart is night by
    /// night, so the query that feeds it must be able to leave them out.
    @Test func napsCanBeExcludedFromTheWindow() throws {
        let store = try MetricsStore(context: ModelContext(LifeOSContainer.make(inMemory: true)),
                                     calendar: calendar)
        try store.upsertSleepRecord(externalID: "night", start: date(2026, 8, 9, 23),
                                    end: date(2026, 8, 10, 7),
                                    attributedDate: date(2026, 8, 10)) { $0.isNap = false }
        try store.upsertSleepRecord(externalID: "nap", start: date(2026, 8, 10, 14),
                                    end: date(2026, 8, 10, 15),
                                    attributedDate: date(2026, 8, 10)) { $0.isNap = true }

        let nights = try store.sleepRecords(from: date(2026, 8, 10), to: date(2026, 8, 10),
                                            includingNaps: false)
        #expect(nights.map(\.externalID) == ["night"])
        #expect(try store.sleepRecords(from: date(2026, 8, 10), to: date(2026, 8, 10)).count == 2)
    }
}
