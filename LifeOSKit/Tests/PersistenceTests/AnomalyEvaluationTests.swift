import Testing
@testable import Persistence

@Suite struct AnomalyEvaluationTests {
    // Baseline
    @Test func baselineIsMeanOfNonNilHistory() {
        let history: [Double?] = [50, nil, 60, 55, 45, 50, 60, 50]  // 7 readings
        #expect(AnomalyEvaluation.baseline(from: history) == 370.0 / 7.0)
    }
    @Test func baselineNeedsSevenReadings() {
        let sparse: [Double?] = [50, 51, 52, 53, 54, 55]  // 6 readings
        #expect(AnomalyEvaluation.baseline(from: sparse) == nil)
    }

    // No data → no verdict, never a finding
    @Test func nilTodayProducesNothing() {
        let history: [Double?] = [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]
        #expect(AnomalyEvaluation.evaluate(metric: "Resting HR", today: nil,
                history: history, threshold: .relativeAbove(0.10)) == nil)
    }
    @Test func insufficientBaselineProducesNothing() {
        #expect(AnomalyEvaluation.evaluate(metric: "Resting HR", today: 90,
                history: [50, 50], threshold: .relativeAbove(0.10)) == nil)
    }

    // relativeAbove: baseline 50, +10% → boundary at 55
    @Test func relativeAboveFlagsAtBoundary() {
        let history: [Double?] = Array(repeating: 50.0, count: 14)
        let finding = AnomalyEvaluation.evaluate(metric: "Resting HR", today: 55,
                history: history, threshold: .relativeAbove(0.10))
        #expect(finding?.direction == .above && finding?.baseline == 50 && finding?.todayValue == 55)
    }
    @Test func relativeAboveStaysQuietBelowBoundary() {
        let history: [Double?] = [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]
        #expect(AnomalyEvaluation.evaluate(metric: "Resting HR", today: 54.9,
                history: history, threshold: .relativeAbove(0.10)) == nil)
    }

    // relativeBelow: baseline 60, −30% → boundary at 42
    @Test func relativeBelowFlagsDrop() {
        let history: [Double?] = [60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60]
        let finding = AnomalyEvaluation.evaluate(metric: "HRV", today: 40,
                history: history, threshold: .relativeBelow(0.30))
        #expect(finding?.direction == .below)
    }

    // absoluteAbove: baseline 33.0, +1.0°C → boundary at 34.0
    @Test func absoluteAboveFlagsSkinTemp() {
        let history: [Double?] = [33, 33, 33, 33, 33, 33, 33, 33, 33, 33, 33, 33, 33, 33]
        let finding = AnomalyEvaluation.evaluate(metric: "Skin temp", today: 34.2,
                history: history, threshold: .absoluteAbove(1.0))
        #expect(finding?.direction == .above)
    }

    // absoluteBelow: baseline 97.0, −3 points → boundary at 94.0
    @Test func absoluteBelowFlagsSpo2() {
        let history: [Double?] = [97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97]
        let finding = AnomalyEvaluation.evaluate(metric: "Blood oxygen", today: 93.5,
                history: history, threshold: .absoluteBelow(3.0))
        #expect(finding?.direction == .below)
    }
    @Test func normalDayProducesNothing() {
        let history: [Double?] = [97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97, 97]
        #expect(AnomalyEvaluation.evaluate(metric: "Blood oxygen", today: 96.8,
                history: history, threshold: .absoluteBelow(3.0)) == nil)
    }
}
