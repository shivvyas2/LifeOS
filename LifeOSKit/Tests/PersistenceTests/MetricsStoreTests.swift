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

    @Test func goalsCreatesDefaultsOnFirstAccessAndReusesThemAfter() throws {
        let store = try makeStore()
        let first = try store.goals()
        first.stepsGoal = 12000

        let second = try store.goals()
        #expect(second.stepsGoal == 12000)
    }
}
