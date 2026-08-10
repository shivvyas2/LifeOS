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
}
