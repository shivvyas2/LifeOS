import Testing
@testable import Persistence

@Suite struct GoalEvaluationTests {
    @Test func defaultTargetsMatchTheSpec() {
        let targets = GoalTargets.default
        #expect(targets.steps == 8000)
        #expect(targets.sleepMinutes == 420)
        #expect(targets.exerciseMinutes == 30)
        #expect(targets.waterML == 2500)
        #expect(targets.requiredCount == 3)
    }

    @Test func aDayWithNoMetricsAtAllIsNoData() {
        let reading = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        #expect(evaluate(reading, against: .default) == .noData)
    }

    @Test func threeOfFourGoalsMetIsOnTarget() {
        let reading = DayReading(steps: 9000, sleepMinutes: 430, exerciseMinutes: 45, waterML: 900)
        #expect(evaluate(reading, against: .default) == .onTarget)
    }

    @Test func twoOfFourGoalsMetIsAMiss() {
        let reading = DayReading(steps: 9000, sleepMinutes: 430, exerciseMinutes: 5, waterML: 900)
        #expect(evaluate(reading, against: .default) == .missed)
    }

    @Test func exactlyAtGoalCounts() {
        let reading = DayReading(steps: 8000, sleepMinutes: 420, exerciseMinutes: 30, waterML: 0)
        #expect(evaluate(reading, against: .default) == .onTarget)
    }

    /// A partially-logged day is judged on what it has. Deliberate: otherwise
    /// forgetting to log water would silently promote a bad day to "no data".
    @Test func partialDataIsJudgedNotExcused() {
        let reading = DayReading(steps: 500, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        #expect(evaluate(reading, against: .default) == .missed)
    }

    @Test func requiredCountIsConfigurable() {
        var targets = GoalTargets.default
        targets.requiredCount = 4
        let reading = DayReading(steps: 9000, sleepMinutes: 430, exerciseMinutes: 45, waterML: 900)
        #expect(evaluate(reading, against: targets) == .missed)
    }
}
