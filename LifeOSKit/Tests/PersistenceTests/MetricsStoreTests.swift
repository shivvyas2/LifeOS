import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct MetricsStoreTests {
    private func makeStore() throws -> MetricsStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MetricsStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func upsertCreatesARowWhenNoneExists() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 5000 }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].steps == 5000)
    }

    @Test func upsertMutatesTheExistingRowRatherThanAddingASecond() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 5000 }
        try store.upsert(date: day) { $0.weightKg = 77.9 }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].steps == 5000)      // not clobbered
        #expect(rows[0].weightKg == 77.9)
    }

    @Test func upsertNormalisesAnyTimestampToStartOfDay() throws {
        let store = try makeStore()
        let midMorning = day.addingTimeInterval(9 * 3600)
        try store.upsert(date: midMorning) { $0.steps = 100 }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].date == day)
    }

    @Test func upsertStampsUpdatedAt() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 100 }
        let first = try store.metrics(from: day, to: day)[0].updatedAt

        try store.upsert(date: day) { $0.steps = 200 }
        let second = try store.metrics(from: day, to: day)[0].updatedAt

        #expect(second >= first)
    }

    @Test func metricsAreReturnedMostRecentFirst() throws {
        let store = try makeStore()
        let earlier = Calendar.current.date(byAdding: .day, value: -3, to: day)!
        try store.upsert(date: earlier) { $0.steps = 1 }
        try store.upsert(date: day) { $0.steps = 2 }

        let rows = try store.metrics(from: earlier, to: day)
        #expect(rows.map(\.steps) == [2, 1])
    }

    /// The batch path must honour the same one-row-per-day invariant as the
    /// single upsert, including when a day already exists.
    @Test func upsertBatchWritesEveryDayAndStillMergesExistingRows() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.weightKg = 80 }

        let dates = (0..<3).map { Calendar.current.date(byAdding: .day, value: -$0, to: day)! }
        try store.upsertBatch(dates: dates) { _, row in row.steps = 1000 }

        let rows = try store.metrics(from: dates.last!, to: day)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.steps == 1000 })
        // The pre-existing row was merged into, not duplicated or clobbered.
        #expect(rows[0].weightKg == 80)
    }

    @Test func goalsCreatesDefaultsOnFirstAccessAndReusesThemAfter() throws {
        let store = try makeStore()
        let first = try store.goals()
        first.stepsGoal = 12000

        let second = try store.goals()
        #expect(second.stepsGoal == 12000)
    }

    @Test func workoutsInARangeComeBackOldestFirstAndIncludeTheLastDay() throws {
        let store = try makeStore()
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
        let second = day.addingTimeInterval(86_400)
        let outside = day.addingTimeInterval(-86_400)

        // Inserted newest first, to prove the sort is the query's doing.
        for (id, start) in [("b", second), ("a", day), ("old", outside)] {
            _ = try store.upsertWorkoutRecord(
                externalID: id, start: start.addingTimeInterval(3_600),
                durationMinutes: 30, activityName: "running"
            ) { _ in }
        }

        let found = try store.workouts(from: day, to: second)

        #expect(found.map(\.externalID) == ["a", "b"])
    }
}
