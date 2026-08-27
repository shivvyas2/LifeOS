import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct ProjectedInputsTests {
    let calendar = Calendar(identifier: .gregorian)

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 27 of August's 31 days lived, 4 remaining.
    var progress: MonthProgress {
        MonthProgress(
            window: MonthWindow(for: date(2026, 8, 1), calendar: calendar),
            now: date(2026, 8, 27), calendar: calendar
        )
    }

    func day(steps: Int? = 9000, sleep: Int? = 450, exercise: Int? = 40, water: Double? = 2600) -> DayReading {
        DayReading(steps: steps, sleepMinutes: sleep, exerciseMinutes: exercise, waterML: water)
    }

    @Test func coastingFillsRemainingDaysAtTheRunningAverage() {
        let inputs = MonthInputs(readings: Array(repeating: day(), count: 27), daysInMonth: 31)
        let coasted = ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)

        #expect(coasted.readings.count == 31)
        #expect(coasted.readings.last?.sleepMinutes == 450)
        #expect(coasted.readings.last?.steps == 9000)
    }

    /// The point of coasting: a month held at its own pace closes where it
    /// already stands. If this drifts, the floor is not a floor.
    @Test func coastingAMonthAlreadyOnTargetLeavesTheScoreWhereItIs() {
        let inputs = MonthInputs(readings: Array(repeating: day(), count: 27), daysInMonth: 31)
        let before = SectorEvidenceFactory.evidence(for: .body, inputs: inputs, answers: [:], calendar: calendar)
        let after = SectorEvidenceFactory.evidence(
            for: .body,
            inputs: ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar),
            answers: [:], calendar: calendar
        )
        #expect(before.proposedScore == after.proposedScore)
    }

    @Test func aMetricNeverLoggedStaysUnloggedWhenCoasting() {
        let inputs = MonthInputs(
            readings: Array(repeating: day(water: nil), count: 27), daysInMonth: 31
        )
        let coasted = ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)
        #expect(coasted.readings.last?.waterML == nil)
    }

    /// Spending nothing more is the best case, not the worst. A coast that
    /// left the tail empty would compute Money's floor above its ceiling.
    @Test func coastingKeepsSpendingAtTheRunningDailyRate() {
        // 27 days, 2700 out, 5400 in: 100 a day out, 200 a day in.
        let inputs = MonthInputs(amounts: [5400, -2700], daysInMonth: 31)
        let coasted = ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)

        let spent = -coasted.amounts.filter { $0 < 0 }.reduce(0, +)
        let earned = coasted.amounts.filter { $0 > 0 }.reduce(0, +)
        #expect(abs(spent - 3100) < 0.001)
        #expect(abs(earned - 6200) < 0.001)
    }

    @Test func coastingGrowsEachBucketAtItsOwnRate() {
        let row = BudgetReport.Row(
            id: UUID(), name: "Eating out", limit: 300, spent: 270,
            adherence: BudgetPeriod.adherence(spent: 270, limit: 300)
        )
        let inputs = MonthInputs(budget: BudgetReport(rows: [row], unclaimed: []), daysInMonth: 31)
        let coasted = ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)

        // 270 over 27 days is 10 a day; 31 days of that is 310, over the limit.
        let projected = try! #require(coasted.budget?.rows.first)
        #expect(abs(projected.spent - 310) < 0.001)
        #expect(projected.isKept == false)
        #expect(projected.adherence < 1)
    }

    @Test func coastingKeepsJournallingAtItsRunningRate() {
        // 9 days written of 27 lived is one day in three; 4 remaining buys 1.
        let written = (1...9).map { date(2026, 8, $0) }
        let inputs = MonthInputs(journalDates: written, daysInMonth: 31)
        let coasted = ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)
        #expect(coasted.journalDates.count == 10)
    }

    /// A rate is already a rate. Coasting does not move it.
    @Test func coastingLeavesTheHabitRateAlone() {
        let inputs = MonthInputs(habitTickRate: 0.4, daysInMonth: 31)
        #expect(ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar).habitTickRate == 0.4)
    }

    @Test func coastingAFinishedMonthChangesNothing() {
        let done = MonthProgress(
            window: MonthWindow(for: date(2026, 8, 1), calendar: calendar),
            now: date(2026, 8, 31), calendar: calendar
        )
        let inputs = MonthInputs(readings: Array(repeating: day(), count: 31), amounts: [-100], daysInMonth: 31)
        let coasted = ProjectedInputs.coasting(inputs, progress: done, calendar: calendar)
        #expect(coasted.readings.count == 31)
        #expect(coasted.amounts == [-100])
    }
}
