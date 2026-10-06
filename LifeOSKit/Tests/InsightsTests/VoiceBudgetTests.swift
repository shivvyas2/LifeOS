import Testing
import Foundation
@testable import Insights

@Suite struct VoiceBudgetTests {
    private func fresh() -> (VoiceBudget, UserDefaults) {
        let suite = "test.voice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        return (VoiceBudget(defaults: defaults, calendar: calendar), defaults)
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func debitsAccumulateWithinAMonth() {
        let (budget, _) = fresh()
        let october = date(2026, 10, 6)
        #expect(budget.used(now: october) == 0)
        #expect(budget.remaining(now: october) == VoiceBudget.monthlyAllowance)
        budget.debit(400, now: october)
        budget.debit(250, now: date(2026, 10, 20))
        #expect(budget.used(now: october) == 650)
        #expect(budget.remaining(now: october) == VoiceBudget.monthlyAllowance - 650)
    }

    @Test func aNewMonthStartsFresh() {
        let (budget, _) = fresh()
        budget.debit(VoiceBudget.monthlyAllowance, now: date(2026, 10, 31))
        #expect(budget.remaining(now: date(2026, 10, 31)) == 0)
        #expect(budget.used(now: date(2026, 11, 1)) == 0)
        #expect(budget.remaining(now: date(2026, 11, 1)) == VoiceBudget.monthlyAllowance)
    }

    @Test func remainingNeverGoesNegativeAndTheKeyNamesTheMonth() {
        let (budget, _) = fresh()
        budget.debit(VoiceBudget.monthlyAllowance + 5_000, now: date(2026, 10, 6))
        #expect(budget.remaining(now: date(2026, 10, 6)) == 0)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(VoiceBudget.key(for: date(2026, 10, 6), calendar: calendar) == "voice.characters.2026-10")
    }
}
