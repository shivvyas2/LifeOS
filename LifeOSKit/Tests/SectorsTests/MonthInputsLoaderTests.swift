import Testing
import Foundation
import SwiftData
import Persistence
@testable import Sectors

@Suite @MainActor struct MonthInputsLoaderTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func makeContext() throws -> ModelContext {
        ModelContext(try LifeOSContainer.make(inMemory: true))
    }

    @Test func aMonthWithNothingRecordedLoadsEmpty() throws {
        let context = try makeContext()
        let inputs = try MonthInputsLoader.load(
            context: context, month: date(2026, 8, 1),
            now: date(2026, 8, 27), calendar: calendar
        )
        #expect(inputs.readings.isEmpty)
        #expect(inputs.amounts.isEmpty)
        #expect(inputs.budget == nil)
        #expect(inputs.habitTickRate == nil)
        #expect(inputs.daysInMonth == 31)
    }

    @Test func metricsInsideTheMonthAreLoadedAndOnesOutsideAreNot() throws {
        let context = try makeContext()
        let metrics = MetricsStore(context: context, calendar: calendar)
        try metrics.upsert(date: date(2026, 8, 10)) { $0.steps = 9000 }
        try metrics.upsert(date: date(2026, 7, 10)) { $0.steps = 4000 }

        let inputs = try MonthInputsLoader.load(
            context: context, month: date(2026, 8, 1),
            now: date(2026, 8, 27), calendar: calendar
        )
        #expect(inputs.readings.count == 1)
        #expect(inputs.readings.first?.steps == 9000)
    }

    @Test func lastMonthsSpendingIsLoadedForTheComparisonRow() throws {
        let context = try makeContext()
        let money = MoneyStore(context: context, calendar: calendar)
        _ = try money.add(date: date(2026, 8, 3), amount: -40, merchant: "Cafe", category: "Food")
        _ = try money.add(date: date(2026, 7, 3), amount: -90, merchant: "Cafe", category: "Food")

        let inputs = try MonthInputsLoader.load(
            context: context, month: date(2026, 8, 1),
            now: date(2026, 8, 27), calendar: calendar
        )
        #expect(inputs.amounts == [-40])
        #expect(inputs.previousAmounts == [-90])
    }

    /// The bug this extraction fixes. `recentTicks` returns one flag per day
    /// in its window and a day with no tick reads false, so ending on the
    /// last day of a month still being lived scores every future day as a
    /// habit missed. On the 27th of a 31 day month that alone caps the rate
    /// at 27/31 no matter how perfect the person has been.
    @Test func habitsAreJudgedOnlyOnTheDaysAlreadyLived() throws {
        let context = try makeContext()
        let plans = PlanStore(context: context, calendar: calendar)
        let habit = try plans.add(kind: .habit, title: "Read")
        for day in 1...27 {
            _ = try plans.toggleTick(for: habit, on: date(2026, 8, day))
        }

        let inputs = try MonthInputsLoader.load(
            context: context, month: date(2026, 8, 1),
            now: date(2026, 8, 27), calendar: calendar
        )
        #expect(inputs.habitTickRate == 1.0)
    }

    /// The two tests above tick every day in the window, so an all-ticked
    /// window of any size passes and an off-by-one in the window's bounds
    /// cannot be caught. Ticking only part of the month pins the numerator
    /// and the denominator at once: 20 of the 27 days already lived.
    @Test func habitsAreJudgedAsAShareOfTheDaysLived() throws {
        let context = try makeContext()
        let plans = PlanStore(context: context, calendar: calendar)
        let habit = try plans.add(kind: .habit, title: "Read")
        for day in 1...20 {
            _ = try plans.toggleTick(for: habit, on: date(2026, 8, day))
        }

        let inputs = try MonthInputsLoader.load(
            context: context, month: date(2026, 8, 1),
            now: date(2026, 8, 27), calendar: calendar
        )
        let rate = try #require(inputs.habitTickRate)
        #expect(abs(rate - 20.0 / 27.0) < 0.001)
    }

    @Test func aClosedMonthStillJudgesEveryDayOfIt() throws {
        let context = try makeContext()
        let plans = PlanStore(context: context, calendar: calendar)
        let habit = try plans.add(kind: .habit, title: "Read")
        for day in 1...31 {
            _ = try plans.toggleTick(for: habit, on: date(2026, 7, day))
        }

        let inputs = try MonthInputsLoader.load(
            context: context, month: date(2026, 7, 1),
            now: date(2026, 8, 27), calendar: calendar
        )
        #expect(inputs.habitTickRate == 1.0)
    }
}
