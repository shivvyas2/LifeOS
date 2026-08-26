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
        #expect(row.whoopAverageHR == 70)
        #expect(row.whoopMaxHR == 170)
    }

    /// Sleep fields beyond performance and total time asleep reach the row too:
    /// coverage for the columns Task 5 added that `derive` was writing but no
    /// test was reading.
    @Test func sleepPerformanceFieldsReachTheRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        let day = date(2026, 8, 10)
        try derivation.derive(sleeps: [
            WhoopSleepSample(externalID: "night", start: date(2026, 8, 9, 23), end: date(2026, 8, 10, 7),
                             performancePercentage: 88, consistencyPercentage: 74,
                             efficiencyPercentage: 91, respiratoryRate: 15.2,
                             sleepDebtMinutes: 40, asleepMinutes: 420)
        ])

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.respiratoryRate == 15.2)
        #expect(row.whoopSleepConsistencyPct == 74)
        #expect(row.whoopSleepEfficiencyPct == 91)
        #expect(row.whoopSleepDebtMinutes == 40)
    }

    /// The five `SleepRecord` columns that reached nobody: `storeSleepRecords`
    /// wrote 9 of the 14 fields Task 5 added and silently dropped the rest.
    @Test func sleepRecordCarriesThePreviouslyDeadFields() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        try derivation.derive(sleeps: [
            WhoopSleepSample(externalID: "night", start: date(2026, 8, 9, 23), end: date(2026, 8, 10, 7),
                             performancePercentage: 88, consistencyPercentage: 74,
                             efficiencyPercentage: 91, sleepDebtMinutes: 40,
                             asleepMinutes: 420, noDataMinutes: 5, sleepCycleCount: 6)
        ])

        let record = try #require(try context.fetch(FetchDescriptor<SleepRecord>()).first)
        #expect(record.consistencyPercentage == 74)
        #expect(record.efficiencyPercentage == 91)
        #expect(record.sleepDebtMinutes == 40)
        #expect(record.noDataMinutes == 5)
        #expect(record.sleepCycleCount == 6)
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
    /// with no network call. Also the regression guard for the mapping drift
    /// between the live client and this rebuild path: `whoopSleepConsistencyPct`
    /// can only reach the row if `rederive` decodes through the same
    /// DTO-to-sample mapping the client uses (`WhoopDTOs.SleepRecord.sample`),
    /// since it is one of the fields the old, hand-duplicated copy of that
    /// mapping silently dropped.
    @Test func rederiveRebuildsTheRowsFromTheArchiveAlone() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let archive = WhoopArchive(context: context)
        let derivation = WhoopDerivation(store: store, archive: archive, calendar: calendar)

        try archive.store(kind: "recovery", externalID: "r-1", payload: Data("""
        {"created_at":"2026-08-10T13:37:33.957Z","score_state":"SCORED",
         "score":{"recovery_score":66,"resting_heart_rate":54,"hrv_rmssd_milli":74.5,
                  "spo2_percentage":97.2,"skin_temp_celsius":33.1}}
        """.utf8))
        try archive.store(kind: "sleep", externalID: "s-1", payload: Data("""
        {"id":"s-1","start":"2026-08-09T23:00:00.000Z","end":"2026-08-10T07:00:00.000Z",
         "nap":false,"score_state":"SCORED",
         "score":{"sleep_performance_percentage":88,"sleep_consistency_percentage":74,
                  "sleep_efficiency_percentage":91}}
        """.utf8))

        let days = try derivation.rederive()
        #expect(days == 1)

        let row = try #require(try store.metrics(from: date(2026, 8, 10), to: date(2026, 8, 10)).first)
        #expect(row.whoopRecoveryPct == 66)
        #expect(row.whoopSleepConsistencyPct == 74)
    }

    @Test func aWorkoutIsStoredAndItsMinutesReachTheDayRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        let day = date(2026, 8, 10)
        try derivation.derive(workouts: [
            WhoopWorkoutSample(externalID: "w-1", start: date(2026, 8, 10, 6),
                               end: date(2026, 8, 10, 7), sportName: "running",
                               strain: 8.2, energyKcal: 375, averageHR: 123, maxHR: 146)
        ])

        let stored = try #require(try context.fetch(FetchDescriptor<WorkoutRecord>()).first)
        #expect(stored.activityName == "running")
        #expect(stored.strain == 8.2)
        #expect(stored.averageHR == 123)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.exerciseMinutes == 60)
    }

    /// The archive's whole promise is that a rebuild reproduces what a sync
    /// produced. A collection the rebuild cannot decode breaks that silently.
    @Test func rederiveRebuildsWorkoutsToo() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let archive = WhoopArchive(context: context)
        let derivation = WhoopDerivation(store: store, archive: archive, calendar: calendar)

        try archive.store(kind: "workout", externalID: "w-1", payload: Data("""
        {"id":"w-1","start":"2026-08-10T06:00:00.000Z","end":"2026-08-10T07:00:00.000Z",
         "sport_name":"running","sport_id":1,"score_state":"SCORED",
         "score":{"strain":8.2,"kilojoule":1569.34,"average_heart_rate":123,
                  "max_heart_rate":146,"distance_meter":1772.77}}
        """.utf8))

        _ = try derivation.rederive()

        let stored = try #require(try context.fetch(FetchDescriptor<WorkoutRecord>()).first)
        #expect(stored.activityName == "running")
        #expect(stored.strain == 8.2)

        let row = try #require(try store.metrics(from: date(2026, 8, 10), to: date(2026, 8, 10)).first)
        #expect(row.exerciseMinutes == 60)
    }

    /// A review noted the minute rollup is only exercised with a single
    /// workout, so the `reduce` is correct by inspection but untested.
    @Test func twoWorkoutsOnOneDaySumTheirMinutes() throws {
        let context = try makeContext()
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context), calendar: calendar)

        try derivation.derive(workouts: [
            WhoopWorkoutSample(externalID: "a", start: date(2026, 8, 10, 6),
                               end: date(2026, 8, 10, 7), sportName: "running"),
            WhoopWorkoutSample(externalID: "b", start: date(2026, 8, 10, 18),
                               end: date(2026, 8, 10, 18), sportName: "lifting"),
        ])

        let row = try #require(try store.metrics(from: date(2026, 8, 10), to: date(2026, 8, 10)).first)
        #expect(row.exerciseMinutes == 60)   // 60 + 0
    }

    @Test func bodyWeightReachesTheDayRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))

        let day = date(2026, 8, 10)
        try derivation.derive(body: (sample: WhoopBodySample(heightMeters: 1.8288,
                                                              weightKilograms: 90.7185,
                                                              maxHeartRate: 200),
                                     date: day))

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.weightKg == 90.7185)
    }

    /// Height and max heart rate are constants, not daily readings. A column
    /// restating the same value on every row is noise, so they are archived and not
    /// columnised.
    @Test func bodyHeightIsNotWrittenToTheDayRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))

        let day = date(2026, 8, 10)
        try derivation.derive(body: (sample: WhoopBodySample(heightMeters: 1.8288,
                                                              weightKilograms: nil,
                                                              maxHeartRate: 200),
                                     date: day))

        // No weight in the sample means no row write at all for weight.
        let rows = try store.metrics(from: day, to: day)
        #expect(rows.first?.weightKg == nil)
    }

    /// The body payload has no date field of its own, unlike the other four
    /// archived kinds, so `rederive` has to fall back to the archive's
    /// `receivedAt` to know which day's row to write the weight onto.
    @Test func rederiveRestoresWeightFromTheArchivedBodyPayload() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let archive = WhoopArchive(context: context)
        let derivation = WhoopDerivation(store: store, archive: archive, calendar: calendar)

        // Noon, not midnight, so the record's day is unambiguous regardless of
        // which local time zone the host running this test is in.
        let receivedAt = date(2026, 8, 10, 12)
        context.insert(WhoopRawRecord(
            kind: "body", externalID: "self",
            payload: Data(#"{"height_meter":1.8288,"weight_kilogram":90.7185,"max_heart_rate":200}"#.utf8),
            receivedAt: receivedAt
        ))
        try context.save()

        let days = try derivation.rederive()
        #expect(days == 1)

        let row = try #require(try store.metrics(from: date(2026, 8, 10), to: date(2026, 8, 10)).first)
        #expect(row.weightKg == 90.7185)
    }

    /// Mirrors `bodyHeightIsNotWrittenToTheDayRow` on the live path: height and
    /// max heart rate are constants, not daily readings, so a rebuild must not
    /// write them to the row either.
    @Test func rederiveDoesNotWriteHeightToTheDayRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let archive = WhoopArchive(context: context)
        let derivation = WhoopDerivation(store: store, archive: archive, calendar: calendar)

        let receivedAt = date(2026, 8, 10, 12)
        context.insert(WhoopRawRecord(
            kind: "body", externalID: "self",
            payload: Data(#"{"height_meter":1.8288,"weight_kilogram":null,"max_heart_rate":200}"#.utf8),
            receivedAt: receivedAt
        ))
        try context.save()

        _ = try derivation.rederive()

        let rows = try store.metrics(from: date(2026, 8, 10), to: date(2026, 8, 10))
        #expect(rows.first?.weightKg == nil)
    }

    /// Nil never overwrites a stored value on the rebuild path either: a
    /// rebuild that replays an archived body payload with no weight must not
    /// clear a weight another sync, or eventually HealthKit, already stored.
    @Test func rederiveNeverClearsAStoredWeightWhenTheArchivedBodyHasNone() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let archive = WhoopArchive(context: context)
        let derivation = WhoopDerivation(store: store, archive: archive, calendar: calendar)

        let day = date(2026, 8, 10)
        try store.upsert(date: day) { $0.weightKg = 77.2 }

        let receivedAt = date(2026, 8, 10, 12)
        context.insert(WhoopRawRecord(
            kind: "body", externalID: "self",
            payload: Data(#"{"height_meter":1.8288,"weight_kilogram":null,"max_heart_rate":200}"#.utf8),
            receivedAt: receivedAt
        ))
        try context.save()

        _ = try derivation.rederive()

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.weightKg == 77.2)
    }

    /// Re-syncing the same workout must correct it, not add a second copy.
    @Test func resyncingAWorkoutUpdatesRatherThanDuplicating() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let derivation = WhoopDerivation(store: MetricsStore(context: context),
                                         archive: WhoopArchive(context: context), calendar: calendar)

        let sample = WhoopWorkoutSample(externalID: "w-1", start: date(2026, 8, 10, 6),
                                        end: date(2026, 8, 10, 7), sportName: "running", strain: 8.2)
        try derivation.derive(workouts: [sample])
        try derivation.derive(workouts: [sample])

        #expect(try context.fetch(FetchDescriptor<WorkoutRecord>()).count == 1)
    }

    @Test func aCalibratingRecoveryIsRecordedAsSuch() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let store = MetricsStore(context: context)
        let derivation = WhoopDerivation(store: store, archive: WhoopArchive(context: context))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

        try derivation.derive(recoveries: [
            WhoopRecoverySample(date: day, recoveryPercentage: 44,
                                restingHeartRate: 64, hrvMilliseconds: 31,
                                isCalibrating: true)
        ])

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.whoopRecoveryIsCalibrating == true)
        #expect(row.whoopRecoveryPct == 44)
    }
}
