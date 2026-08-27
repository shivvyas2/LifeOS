import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct LeverTests {

    @Test func bodyIsMovedByTheFourDailyMetrics() {
        #expect(Lever.all(for: .body) == [.sleep, .exercise, .steps, .water])
    }

    /// Growth scores on the same four averages through its targets rule, so
    /// it moves on the same levers. Its goal rows are not projected: a goal
    /// closing is not something a remaining day guarantees.
    @Test func growthIsMovedByTheSameFourMetrics() {
        #expect(Lever.all(for: .growth) == [.sleep, .exercise, .steps, .water])
    }

    @Test func missionIsMovedByHabitsAlone() {
        #expect(Lever.all(for: .mission) == [.habits])
    }

    @Test func mindAndSoulAreMovedByJournalling() {
        #expect(Lever.all(for: .mind) == [.journal])
        #expect(Lever.all(for: .soul) == [.journal])
    }

    @Test func moneyIsMovedBySpending() {
        #expect(Lever.all(for: .money) == [.spend])
    }

    /// Family, romance and friends score from answers alone. Nothing a
    /// remaining day does changes them, so offering a lever would be a lie.
    @Test func theRelationalSectorsHaveNoLevers() {
        #expect(Lever.all(for: .family).isEmpty)
        #expect(Lever.all(for: .romance).isEmpty)
        #expect(Lever.all(for: .friends).isEmpty)
    }

    @Test func aMetricNeverLoggedIsNotALever() {
        let noWater = MonthInputs(
            readings: [DayReading(steps: 9000, sleepMinutes: 400, exerciseMinutes: 20, waterML: nil)]
        )
        #expect(Lever.water.tracked(in: noWater) == false)
        #expect(Lever.steps.tracked(in: noWater))
    }

    @Test func spendIsOnlyALeverWhenBucketsExist() {
        #expect(Lever.spend.tracked(in: MonthInputs()) == false)
        let budgeted = MonthInputs(budget: BudgetReport(rows: [], unclaimed: []))
        #expect(Lever.spend.tracked(in: budgeted))
    }

    @Test func habitsAreOnlyALeverWhenThereAreHabitDaysToJudge() {
        #expect(Lever.habits.tracked(in: MonthInputs()) == false)
        #expect(Lever.habits.tracked(in: MonthInputs(habitTickRate: 0.4)))
    }

    @Test func journallingIsOnlyALeverOnceSomethingHasBeenWritten() {
        #expect(Lever.journal.tracked(in: MonthInputs()) == false)
        #expect(Lever.journal.tracked(in: MonthInputs(journalDates: [.now])))
    }
}
