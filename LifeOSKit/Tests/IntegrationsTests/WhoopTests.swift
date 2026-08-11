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

@Suite @MainActor struct WhoopIngestionTests {
    private func makeStore() throws -> MetricsStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MetricsStore(context: ModelContext(container))
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
        let store = try makeStore()
        let ingestion = WhoopIngestion(store: store, calendar: calendar)
        let day = date(2026, 3, 10)

        try ingestion.ingest(
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
        let store = try makeStore()
        let ingestion = WhoopIngestion(store: store, calendar: calendar)

        try ingestion.ingest(sleeps: [
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
        let store = try makeStore()
        let day = date(2026, 3, 10)
        try store.upsert(date: day) { $0.steps = 9_100; $0.weightKg = 77.2 }

        try WhoopIngestion(store: store, calendar: calendar)
            .ingest(recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 65,
                                                     restingHeartRate: nil, hrvMilliseconds: nil)])

        let row = try store.metrics(from: day, to: day)[0]
        #expect(row.steps == 9_100)
        #expect(row.weightKg == 77.2)
        #expect(row.whoopRecoveryPct == 65)
    }

    /// A missing field means "no reading", never "clear the stored value".
    @Test func nilReadingsDoNotWipeExistingValues() throws {
        let store = try makeStore()
        let day = date(2026, 3, 10)
        let ingestion = WhoopIngestion(store: store, calendar: calendar)

        try ingestion.ingest(recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: 70,
                                                             restingHeartRate: 50, hrvMilliseconds: 90)])
        try ingestion.ingest(recoveries: [WhoopRecoverySample(date: day, recoveryPercentage: nil,
                                                             restingHeartRate: nil, hrvMilliseconds: nil)])

        let row = try store.metrics(from: day, to: day)[0]
        #expect(row.whoopRecoveryPct == 70)
        #expect(row.restingHR == 50)
        #expect(row.hrvMs == 90)
    }

    @Test func resyncingTheSameDayDoesNotCreateASecondRow() throws {
        let store = try makeStore()
        let day = date(2026, 3, 10)
        let ingestion = WhoopIngestion(store: store, calendar: calendar)

        for value in [60.0, 75.0] {
            try ingestion.ingest(cycles: [WhoopCycleSample(date: day, dayStrain: value)])
        }

        let rows = try store.metrics(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].whoopDayStrain == 75)
    }
}
