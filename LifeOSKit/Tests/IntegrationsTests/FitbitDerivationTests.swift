import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// Payloads to values on the spine. The mapping is the part that can be
/// perfectly decoded and still land in the wrong column.
@Suite @MainActor struct FitbitDerivationTests {

    private func store() throws -> MetricsStore {
        MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    /// The fixture's own day, resolved the same way the derivation resolves it,
    /// so the test does not silently depend on the machine's time zone.
    private var day: Date {
        FitbitDerivation.parseDay("2026-08-26", calendar: .current)!
    }

    private func decode(_ json: String) throws -> FitbitPayloads {
        try JSONDecoder().decode(FitbitPayloads.self, from: Data(json.utf8))
    }

    private var fixture: FitbitPayloads {
        try! decode("""
        {"sleep":{"sleep":[{"dateOfSleep":"2026-08-26","efficiency":91,
           "minutesAsleep":432,"minutesAwake":48,"timeInBed":480,"type":"stages",
           "levels":{"summary":{"deep":{"count":4,"minutes":78},
             "light":{"count":29,"minutes":244},"rem":{"count":6,"minutes":110},
             "wake":{"count":31,"minutes":48}}}}]},
         "hrv":{"hrv":[{"dateTime":"2026-08-26","value":{"dailyRmssd":34.2,"deepRmssd":41.6}}]},
         "restingHeartRate":{"activities-heart":[
           {"dateTime":"2026-08-26","value":{"restingHeartRate":54}}]}}
        """)
    }

    /// Fitbit calls it light and Apple calls it core. They are the same stage
    /// under two vendors' names, and filing Fitbit's light anywhere else would
    /// leave the sleep panel with a blank row and an unexplained total.
    @Test func lightSleepBecomesCore() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(fixture)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.extra(HealthMetric.coreSleepMinutes.rawValue) == 244)
        #expect(row.extra(HealthMetric.deepSleepMinutes.rawValue) == 78)
        #expect(row.extra(HealthMetric.remSleepMinutes.rawValue) == 110)
        #expect(row.sleepMinutes == 432)
    }

    @Test func everyDerivedValueIsAttributedToFitbit() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(fixture)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.source(HealthMetric.sleepMinutes.rawValue) == MetricSource.fitbit.rawValue)
        #expect(row.source(HealthMetric.coreSleepMinutes.rawValue) == MetricSource.fitbit.rawValue)
    }

    /// Whoop is primary by default, so Fitbit fills its gaps and does not
    /// overwrite what the chosen strap measured.
    @Test func fitbitDoesNotOverwriteThePrimaryStrap() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.sleepMinutes = 400
            row.setSource(HealthMetric.sleepMinutes.rawValue, MetricSource.whoop.rawValue)
        }

        try FitbitDerivation(store: store).derive(fixture)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 400)
    }

    /// But when the user names Fitbit as primary, it wins.
    @Test func fitbitOverwritesWhenItIsPrimary() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.sleepMinutes = 400
            row.setSource(HealthMetric.sleepMinutes.rawValue, MetricSource.whoop.rawValue)
        }

        try FitbitDerivation(store: store, ranking: SourceRanking(primaryWearable: .fitbit))
            .derive(fixture)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 432)
    }

    /// deepRmssd is a different measurement from dailyRmssd. Averaging them or
    /// writing both to hrvMs would be a fabricated number.
    @Test func onlyTheDailyRmssdBecomesHRV() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(fixture)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.hrvMs == 34.2)
    }

    @Test func restingHeartRateReachesItsOwnColumn() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(fixture)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 54)
    }

    /// An empty payload writes nothing at all, rather than a row of zeroes.
    @Test func anEmptyPayloadWritesNothing() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(FitbitPayloads())
        #expect(try store.metrics(from: day, to: day).isEmpty)
    }

    /// A classic sleep log has no stages. The night still counts; the stage
    /// rows are simply absent, not zero.
    @Test func anUnstagedNightStillWritesItsTotal() throws {
        let store = try store()
        try FitbitDerivation(store: store).derive(try decode("""
        {"sleep":{"sleep":[{"dateOfSleep":"2026-08-26","efficiency":88,
          "minutesAsleep":360,"minutesAwake":20,"timeInBed":380,"type":"classic"}]}}
        """))

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 360)
        #expect(row.extra(HealthMetric.deepSleepMinutes.rawValue) == nil)
    }

    /// A GPS-less VO2 max arrives as a range. Storing the lower bound would
    /// understate every one of them.
    @Test func aVO2MaxRangeBecomesItsMidpoint() {
        #expect(FitbitDerivation.parseVO2Max("46") == 46)
        #expect(FitbitDerivation.parseVO2Max("40-44") == 42)
        #expect(FitbitDerivation.parseVO2Max("nonsense") == nil)
    }

    /// Fitbit sends a bare yyyy-MM-dd in local time. Read as UTC, every night
    /// west of UTC lands on the day before.
    @Test func aDateIsReadInTheUsersOwnTimeZone() throws {
        let day = try #require(FitbitDerivation.parseDay("2026-08-26", calendar: .current))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)

        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 26)
    }
}
