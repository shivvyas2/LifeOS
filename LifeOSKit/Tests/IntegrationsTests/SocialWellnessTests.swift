import Testing
import Foundation
import SwiftData
import Persistence
@testable import Integrations

@Suite struct SocialWellnessTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))! }
    private func reading(_ offset: Int = 0, source: String = "whoop", exercise: Int? = 30, sleep: Int? = 420,
                         hrv: Double? = 50, rhr: Double? = 60, calibrating: Bool = false) -> WellnessReading {
        WellnessReading(date: calendar.date(byAdding: .day, value: offset, to: today)!, exerciseMinutes: exercise,
            sleepMinutes: sleep, hrv: hrv, restingHR: rhr,
            sources: ["exerciseMinutes": source, "sleepMinutes": source, "hrvMs": source, "restingHR": source], calibrating: calibrating)
    }
    private func scores(_ rows: [WellnessReading]) -> [SocialWellnessDay] {
        SocialWellness.scores(readings: rows, exerciseGoal: 30, sleepGoal: 420, now: today, calendar: calendar)
    }
    @Test(arguments: ["whoop", "appleHealth", "fitbit"]) func sameInputsUseSameScale(source: String) throws {
        let rows = (1...7).map { reading(-$0, source: source) } + [reading(source: source)]
        let result = try #require(scores(rows).last)
        #expect(result.effort == 100 && result.rest == 100 && result.recharge == 50)
        #expect(result.effortSource == source && result.rechargeSource == source && result.restSource == source)
    }
    @Test func missingAndRecordedZeroRemainDifferent() throws {
        let zero = try #require(scores([reading(exercise: 0, sleep: 0)]).first)
        #expect(zero.effort == 0 && zero.rest == 0 && zero.recharge == nil)
        let missing = try #require(scores([reading(exercise: nil, sleep: nil)]).first)
        #expect(missing.effort == nil && missing.rest == nil && missing.restSource == nil)
    }
    @Test func goalProgressIsCappedAndInvalidValuesAreAbsent() throws {
        let capped = try #require(scores([reading(exercise: 90, sleep: 600)]).first)
        #expect(capped.effort == 100 && capped.rest == 100)
        let invalid = try #require(scores([reading(exercise: -2, sleep: 1600)]).first)
        #expect(invalid.effort == nil && invalid.rest == nil)
    }
    @Test func manualAndUnattributedDataDoNotEnterRankings() throws {
        let manual = try #require(scores([reading(source: "manual")]).first)
        #expect(manual.effort == nil && manual.rest == nil && manual.recharge == nil)
    }
    @Test func baselineCannotMixProvidersOrUseTodaysReading() throws {
        let result = try #require(scores((1...7).map { reading(-$0, source: "appleHealth") } + [reading()]).last)
        #expect(result.recharge == nil)
        #expect(try #require(scores((0...6).map { reading(-$0) }).last).recharge == nil)
    }
    @Test func duplicateDaysCannotCompleteCalibration() throws {
        let rows = Array(repeating: reading(-1), count: 7) + [reading()]
        #expect(try #require(scores(rows).last).recharge == nil)
    }
    @Test func oldBaselineAndCalibrationDoNotCount() throws {
        #expect(try #require(scores((30...36).map { reading(-$0) } + [reading()]).last).recharge == nil)
        #expect(try #require(scores((1...7).map { reading(-$0) } + [reading(calibrating: true)]).last).recharge == nil)
    }
    @Test func rechargeMovesRelativeToPersonalSignals() throws {
        let baseline = (1...7).map { reading(-$0) }
        let better = try #require(scores(baseline + [reading(hrv: 60, rhr: 54)]).last)
        let lower = try #require(scores(baseline + [reading(hrv: 40, rhr: 66)]).last)
        #expect(better.recharge == 66 && lower.recharge == 34)
    }
    @Test func nonFiniteSignalsCannotProduceAValidScore() throws {
        let baseline = (1...7).map { reading(-$0) }
        #expect(try #require(scores(baseline + [reading(hrv: .nan)]).last).recharge == nil)
    }
    @Test func dateFilteringDoesNotRelabelOldReadings() {
        #expect(scores([reading(-2), reading(1)]).isEmpty)
        #expect(scores([reading(-1), reading()]).map(\.day) == ["2026-09-13", "2026-09-14"])
    }
    @Test func serverDayUsesGregorianYearInOtherCalendarLocales() {
        var local = Calendar(identifier: .buddhist); local.timeZone = calendar.timeZone
        #expect(SocialWellness.dayKey(today, calendar: local) == "2026-09-14")
    }
    @Test func localDayRespectsDateBoundary() {
        var local = calendar; local.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        #expect(SocialWellness.dayKey(today, calendar: local) == "2026-09-13")
    }
}

@Suite @MainActor struct FitbitLeaderboardIngestionTests {
    @Test func completeActivityMinutesReachTheSharedDailyColumnOnce() throws {
        let payload = try JSONDecoder().decode(FitbitPayloads.self, from: Data(#"{"fairlyActiveMinutes":{"activities-minutesFairlyActive":[{"dateTime":"2026-09-14","value":"20"}]},"veryActiveMinutes":{"activities-minutesVeryActive":[{"dateTime":"2026-09-14","value":"10"}]}}"#.utf8))
        let store = MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
        let derivation = FitbitDerivation(store: store)
        try derivation.derive(payload); try derivation.derive(payload)
        let day = try #require(FitbitDerivation.parseDay("2026-09-14", calendar: .current))
        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.exerciseMinutes == 30)
        #expect(row.source("exerciseMinutes") == "fitbit")
    }
    @Test func napCannotReplaceTheMainNight() throws {
        let payload = try JSONDecoder().decode(FitbitPayloads.self, from: Data(#"{"sleep":{"sleep":[{"dateOfSleep":"2026-09-14","isMainSleep":true,"minutesAsleep":420},{"dateOfSleep":"2026-09-14","isMainSleep":false,"minutesAsleep":25}]}}"#.utf8))
        #expect(FitbitDerivation.days(from: payload).first?.values[.sleepMinutes] == 420)
    }
    @Test func incompleteActivityIsNotInventedAsZero() throws {
        let payload = try JSONDecoder().decode(FitbitPayloads.self, from: Data(#"{"fairlyActiveMinutes":{"activities-minutesFairlyActive":[{"dateTime":"2026-09-14","value":"20"}]}}"#.utf8))
        #expect(FitbitDerivation.days(from: payload).isEmpty)
    }
}
