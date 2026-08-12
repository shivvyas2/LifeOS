import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

@Suite struct WhoopOAuthTests {
    private let clientID = "test-client-id"
    private let redirect = "lifeos://whoop-callback"

    @Test func authorizeURLCarriesPKCEAndNoSecret() throws {
        let session = WhoopOAuth.session(clientID: clientID, redirectURI: redirect)
        let items = URLComponents(url: session.url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(value("client_id") == clientID)
        #expect(value("response_type") == "code")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge")?.isEmpty == false)

        // The whole point: nothing resembling a secret is in the URL, and the
        // verifier itself never leaves the device at this stage.
        let url = session.url.absoluteString
        #expect(!url.contains("client_secret"))
        #expect(!url.contains(session.verifier))
    }

    @Test func challengeIsBase64URLWithoutPadding() {
        let challenge = WhoopOAuth.challenge(for: "verifier")
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(!challenge.contains("="))
    }

    @Test func codeIsExtractedWhenStateMatches() throws {
        let session = WhoopOAuth.session(clientID: clientID, redirectURI: redirect)
        let url = URL(string: "\(redirect)?code=abc123&state=\(session.state)")!
        #expect(try WhoopOAuth.code(from: url, expectedState: session.state) == "abc123")
    }

    /// A forged redirect must not get its code exchanged.
    @Test func mismatchedStateIsRejected() {
        let url = URL(string: "\(redirect)?code=abc123&state=attacker")!
        #expect(throws: WhoopAuthError.stateMismatch) {
            try WhoopOAuth.code(from: url, expectedState: "ours")
        }
    }

    @Test func userDenialIsSurfacedRatherThanTreatedAsMissingCode() {
        let url = URL(string: "\(redirect)?error=access_denied&state=ours")!
        #expect(throws: WhoopAuthError.denied("access_denied")) {
            try WhoopOAuth.code(from: url, expectedState: "ours")
        }
    }

    @Test func verifiersDifferBetweenSessions() {
        let first = WhoopOAuth.session(clientID: clientID, redirectURI: redirect)
        let second = WhoopOAuth.session(clientID: clientID, redirectURI: redirect)
        #expect(first.verifier != second.verifier)
        #expect(first.state != second.state)
    }

    /// Read before the verifier is needed, so a redirect can be matched to the
    /// attempt that started it when several are in flight.
    @Test func stateIsReadableFromARedirectOnItsOwn() {
        let url = URL(string: "\(redirect)?code=abc123&state=ours")!
        #expect(WhoopOAuth.state(in: url) == "ours")
    }

    @Test func aRedirectWithoutStateHasNoneToMatch() {
        let url = URL(string: "\(redirect)?code=abc123")!
        #expect(WhoopOAuth.state(in: url) == nil)
    }
}

@Suite @MainActor struct WhoopDerivationTests {
    private func makeContext() throws -> ModelContext {
        let container = try LifeOSContainer.make(inMemory: true)
        return ModelContext(container)
    }

    private func makeStore() throws -> MetricsStore {
        MetricsStore(context: try makeContext())
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func recoveryStrainAndSleepLandOnOneRowPerDay() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)
        let day = date(2026, 3, 10)

        try derivation.derive(
            recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 72,
                                             restingHeartRate: 51, hrvMilliseconds: 88)],
            sleeps: [WhoopSleepSample(start: date(2026, 3, 9, 23), end: date(2026, 3, 10, 7),
                                      performancePercentage: 91, asleepMinutes: 430)],
            cycles: [WhoopCycleSample(date: day, dayStrain: 14.2)]
        )

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].whoopRecoveryPct == 72)
        #expect(rows[0].whoopDayStrain == 14.2)
        #expect(rows[0].whoopSleepPerformancePct == 91)
        #expect(rows[0].sleepMinutes == 430)
        #expect(rows[0].syncedAt != nil)
    }

    /// Sleep belongs to the morning you woke up. A night starting 23:00 on the
    /// 9th and ending 07:00 on the 10th is the 10th's sleep.
    @Test func sleepIsAttributedToTheWakeUpDayNotTheBedtimeDay() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        try derivation.derive(sleeps: [
            WhoopSleepSample(start: date(2026, 3, 9, 23), end: date(2026, 3, 10, 7),
                             performancePercentage: 88, asleepMinutes: 400)
        ])

        let ninth = try store.metrics(from: date(2026, 3, 9), to: date(2026, 3, 9))
        let tenth = try store.metrics(from: date(2026, 3, 10), to: date(2026, 3, 10))
        #expect(ninth.isEmpty)
        #expect(tenth.first?.sleepMinutes == 400)
    }

    /// HealthKit owns steps and weight on the same row. A Whoop sync must merge.
    @Test func syncPreservesFieldsOwnedByOtherSources() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let day = date(2026, 3, 10)
        try store.upsert(date: day) { $0.steps = 9_100; $0.weightKg = 77.2 }

        try WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)
            .derive(recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 65,
                                                     restingHeartRate: nil, hrvMilliseconds: nil)])

        let row = try store.metrics(from: day, to: day)[0]
        #expect(row.steps == 9_100)
        #expect(row.weightKg == 77.2)
        #expect(row.whoopRecoveryPct == 65)
    }

    /// A missing field means "no reading", never "clear the stored value".
    @Test func nilReadingsDoNotWipeExistingValues() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let day = date(2026, 3, 10)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        try derivation.derive(recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 70,
                                                             restingHeartRate: 50, hrvMilliseconds: 90)])
        try derivation.derive(recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: nil,
                                                             restingHeartRate: nil, hrvMilliseconds: nil)])

        let row = try store.metrics(from: day, to: day)[0]
        #expect(row.whoopRecoveryPct == 70)
        #expect(row.restingHR == 50)
        #expect(row.hrvMs == 90)
    }

    @Test func resyncingTheSameDayDoesNotCreateASecondRow() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let day = date(2026, 3, 10)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        for value in [60.0, 75.0] {
            try derivation.derive(cycles: [WhoopCycleSample(date: day, dayStrain: value)])
        }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].whoopDayStrain == 75)
    }

    @Test func spo2SkinTempAndCaloriesReachTheRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))

        let day = date(2026, 8, 10)
        try derivation.derive(
            recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 66,
                                             restingHeartRate: 54, hrvMilliseconds: 74.5,
                                             spo2Percentage: 97.2, skinTempCelsius: 33.1)],
            sleeps: [],
            cycles: [WhoopCycleSample(date: day, dayStrain: 12.7, calories: 2151.6,
                                      averageHR: 70, maxHR: 170)]
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.spo2Percentage == 97.2)
        #expect(row.skinTempCelsius == 33.1)
        #expect(row.whoopCalories == 2151.6)
    }

    /// A nap must not overwrite the night's sleep on the daily row, but it is still
    /// stored as a record of its own rather than dropped.
    @Test func aNapIsStoredButDoesNotTouchTheDayRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        // An explicit calendar is required here, matching the sibling
        // cross-midnight tests above: the sleep sample's end time is
        // attributed via its own hour, not the hour-0 `day` marker below, so
        // derivation and query must agree on one calendar or the two can
        // land on different local days depending on the host's time zone.
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        let day = date(2026, 8, 10)
        try derivation.derive(
            recoveries: [],
            sleeps: [
                WhoopSleepSample(externalID: "night", start: date(2026, 8, 9, 23),
                                 end: date(2026, 8, 10, 7), isNap: false,
                                 performancePercentage: 88, asleepMinutes: 420),
                WhoopSleepSample(externalID: "nap", start: date(2026, 8, 10, 14),
                                 end: date(2026, 8, 10, 14), isNap: true,
                                 performancePercentage: nil, asleepMinutes: 30),
            ],
            cycles: []
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.sleepMinutes == 420)        // the night, not the nap, not the sum

        let records = try context.fetch(FetchDescriptor<SleepRecord>())
        #expect(records.count == 2)             // both stored
        #expect(records.contains { $0.isNap == true })
    }

    /// The whole point of the archive: rebuild the metrics from stored payloads
    /// with no network call.
    @Test func rederiveRebuildsTheRowsFromTheArchiveAlone() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let archive = WhoopArchive(context: context)
        let derivation = WhoopDerivation(store: store, archive: archive)

        try archive.store(kind: "recovery", externalID: "r-1", payload: Data("""
        {"created_at":"2026-08-10T13:37:33.957Z","score_state":"SCORED",
         "score":{"recovery_score":66,"resting_heart_rate":54,"hrv_rmssd_milli":74.5,
                  "spo2_percentage":97.2,"skin_temp_celsius":33.1}}
        """.utf8))

        let days = try derivation.rederive()
        #expect(days == 1)

        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_786_282_653))
        let rows = try store.metrics(from: day.addingTimeInterval(-86_400 * 2),
                                     to: day.addingTimeInterval(86_400 * 2))
        #expect(rows.contains { $0.whoopRecoveryPct == 66 })
    }
}
