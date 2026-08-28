import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct LeverageTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    var progress: MonthProgress {
        MonthProgress(
            window: MonthWindow(for: date(2026, 8, 1), calendar: calendar),
            now: date(2026, 8, 27), calendar: calendar
        )
    }

    func ranked(_ sector: LifeSector, _ inputs: MonthInputs) -> [LeverDelta] {
        Leverage.ranked(
            for: sector, inputs: inputs, progress: progress, answers: [:], calendar: calendar
        )
    }

    /// Sleep and exercise are below target; steps and water are already past
    /// it. The two that can still move must rank above the two that cannot.
    /// Which of the two leads is arithmetic, not a decision, so it is not
    /// pinned here.
    @Test func leversAreRankedByWhatTheyAreWorth() {
        let reading = DayReading(steps: 20000, sleepMinutes: 200, exerciseMinutes: 5, waterML: 2600)
        let inputs = MonthInputs(
            readings: Array(repeating: reading, count: 27), targets: .default, daysInMonth: 31
        )
        let deltas = ranked(.body, inputs)
        let movable: Set<Lever> = [.sleep, .exercise]

        #expect(deltas.count == 4)
        #expect(deltas == deltas.sorted { $0.delta > $1.delta })
        #expect(deltas.prefix(2).allSatisfy { movable.contains($0.lever) })
        #expect(deltas.suffix(2).allSatisfy { $0.delta == 0 })
    }

    @Test func aLeverAlreadyAtTargetIsWorthNothing() {
        let reading = DayReading(steps: 20000, sleepMinutes: 200, exerciseMinutes: 5, waterML: 2600)
        let inputs = MonthInputs(
            readings: Array(repeating: reading, count: 27), targets: .default, daysInMonth: 31
        )
        let steps = try! #require(ranked(.body, inputs).first { $0.lever == .steps })
        #expect(steps.delta == 0)
    }

    @Test func anUntrackedMetricIsNotOfferedAsALever() {
        let reading = DayReading(steps: 9000, sleepMinutes: 400, exerciseMinutes: 20, waterML: nil)
        let inputs = MonthInputs(
            readings: Array(repeating: reading, count: 27), targets: .default, daysInMonth: 31
        )
        #expect(ranked(.body, inputs).contains { $0.lever == .water } == false)
    }

    @Test func aSectorScoredOnlyFromAnswersHasNoLevers() {
        #expect(ranked(.family, MonthInputs(daysInMonth: 31)).isEmpty)
    }

    @Test func aFinishedMonthHasNothingLeftToMove() {
        let reading = DayReading(steps: 200, sleepMinutes: 200, exerciseMinutes: 0, waterML: 100)
        let inputs = MonthInputs(
            readings: Array(repeating: reading, count: 31), targets: .default, daysInMonth: 31
        )
        let done = MonthProgress(
            window: MonthWindow(for: date(2026, 8, 1), calendar: calendar),
            now: date(2026, 8, 31), calendar: calendar
        )
        let deltas = Leverage.ranked(
            for: .body, inputs: inputs, progress: done, answers: [:], calendar: calendar
        )
        #expect(deltas.allSatisfy { $0.delta == 0 })
    }

    /// A delta is never negative: perfecting a lever cannot make a month
    /// worse, and a negative row would read as advice to stop trying.
    @Test func noLeverIsWorthLessThanNothing() {
        let reading = DayReading(steps: 20000, sleepMinutes: 600, exerciseMinutes: 90, waterML: 4000)
        let inputs = MonthInputs(
            readings: Array(repeating: reading, count: 27), targets: .default, daysInMonth: 31
        )
        #expect(ranked(.body, inputs).allSatisfy { $0.delta >= 0 })
    }

    @Test func moneyRanksSpendingWhenBucketsExist() {
        let row = BudgetReport.Row(
            id: UUID(), name: "Eating out", limit: 300, spent: 290,
            adherence: BudgetPeriod.adherence(spent: 290, limit: 300)
        )
        let inputs = MonthInputs(
            amounts: [3000, -1500], budget: BudgetReport(rows: [row], unclaimed: []),
            daysInMonth: 31
        )
        #expect(ranked(.money, inputs).map(\.lever) == [.spend])
    }

    /// The ranking runs on `Evidence.proposedValue`, not `proposedScore`.
    /// Sleep is worth about 0.81 of a point here: real, and invisible to a
    /// ranking that rounds before subtracting, which would call it worthless.
    @Test func aLeverWorthLessThanAWholePointIsStillWorthSomething() {
        let reading = DayReading(steps: 20000, sleepMinutes: 200, exerciseMinutes: 5, waterML: 2600)
        let inputs = MonthInputs(
            readings: Array(repeating: reading, count: 27), targets: .default, daysInMonth: 31
        )
        let sleep = try! #require(ranked(.body, inputs).first { $0.lever == .sleep })
        #expect(sleep.delta > 0)
        #expect(sleep.delta < 1)
    }
}
