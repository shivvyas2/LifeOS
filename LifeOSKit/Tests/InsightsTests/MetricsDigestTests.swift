import Testing
import Foundation
import SwiftData
import Persistence
@testable import Insights

@Suite @MainActor struct MetricsDigestTests {

    private func makeStore() throws -> MetricsStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MetricsStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func aDigestCarriesOneEntryPerDay() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 8_000 }

        let digest = MetricsDigest.from(try store.metrics(from: day, to: day))

        #expect(digest.days.count == 1)
        #expect(digest.days[0].steps == 8_000)
    }

    /// A missing value and a zero must never become the same thing, which is
    /// the rule `DailyMetrics` is built around. The digest inherits it.
    @Test func aMissingMetricStaysNilRatherThanBecomingZero() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 8_000 }

        let digest = MetricsDigest.from(try store.metrics(from: day, to: day))

        #expect(digest.days[0].steps == 8_000)
        #expect(digest.days[0].sleepMinutes == nil)
        #expect(digest.days[0].recoveryPct == nil)
    }

    @Test func averagesIgnoreDaysWithNoReading() throws {
        let store = try makeStore()
        let second = day.addingTimeInterval(86_400)
        try store.upsert(date: day) { $0.steps = 10_000 }
        try store.upsert(date: second) { $0.weightKg = 78 }   // no steps

        let digest = MetricsDigest.from(try store.metrics(from: day, to: second))

        // 10_000 over one contributing day, not 5_000 over two.
        #expect(digest.averages.steps == 10_000)
    }

    @Test func averagesAreNilWhenNothingContributes() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.weightKg = 78 }

        let digest = MetricsDigest.from(try store.metrics(from: day, to: day))

        #expect(digest.averages.steps == nil)
    }

    /// The privacy rule made mechanical: whatever else changes about the
    /// digest, the raw Whoop surface must not appear in what we send.
    @Test func thePromptTextCarriesNoRawWhoopFields() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.steps = 8_000
            $0.whoopRecoveryPct = 62
            $0.hrvMs = 41.2
            $0.spo2Percentage = 97.5
            $0.skinTempCelsius = 33.4
            $0.respiratoryRate = 14.2
        }

        let text = MetricsDigest.from(try store.metrics(from: day, to: day)).promptLines

        #expect(text.contains("62"))              // the aggregate is wanted
        #expect(text.contains("41.2") == false)   // HRV series is not
        #expect(text.contains("97.5") == false)
        #expect(text.contains("33.4") == false)
        #expect(text.contains("14.2") == false)
    }
}
