import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BodyScorerTests {

    private func day(steps: Int? = 9000, sleep: Int? = 450, exercise: Int? = 40) -> DayReading {
        DayReading(steps: steps, sleepMinutes: sleep, exerciseMinutes: exercise, waterML: 2600)
    }

    @Test func aMonthOnTargetScoresAtTheTop() {
        let scorer = BodyScorer(
            readings: Array(repeating: day(), count: 30), targets: .default
        )
        #expect(scorer.evidence().proposedScore == 10)
        #expect(scorer.sector == .body)
    }

    @Test func aMonthOfMissesScoresLow() {
        let poor = day(steps: 200, sleep: 200, exercise: 0)
        let scorer = BodyScorer(readings: Array(repeating: poor, count: 30), targets: .default)
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! <= 2)
    }

    /// Leaving the watch on the charger is not a failure, so blank days are
    /// excluded rather than counted as misses.
    @Test func daysWithNoDataDoNotDragTheScoreDown() {
        let blank = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        let mixed = Array(repeating: day(), count: 10) + Array(repeating: blank, count: 20)
        let scorer = BodyScorer(readings: mixed, targets: .default)
        #expect(scorer.evidence().proposedScore == 10)
    }

    @Test func aMonthWithNoDataAtAllProposesNothing() {
        let blank = DayReading(steps: nil, sleepMinutes: nil, exerciseMinutes: nil, waterML: nil)
        let scorer = BodyScorer(readings: Array(repeating: blank, count: 30), targets: .default)
        #expect(scorer.evidence().proposedScore == nil)
        #expect(scorer.evidence().rows.isEmpty)
    }

    @Test func noReadingsAtAllProposesNothing() {
        #expect(BodyScorer(readings: [], targets: .default).evidence().proposedScore == nil)
    }

    @Test func theEvidenceNamesWhatItCounted() {
        let scorer = BodyScorer(readings: Array(repeating: day(), count: 30), targets: .default)
        let labels = scorer.evidence().rows.map(\.label)
        #expect(labels.contains("days on target"))
        #expect(labels.contains("sleep vs goal"))
        #expect(labels.contains("exercise vs goal"))
    }

    @Test func theDaysOnTargetRowShowsTheCount() {
        let mixed = Array(repeating: day(), count: 15)
            + Array(repeating: day(steps: 100, sleep: 100, exercise: 0), count: 15)
        let scorer = BodyScorer(readings: mixed, targets: .default)
        let row = scorer.evidence().rows.first { $0.label == "days on target" }
        #expect(row?.value == "15/30")
        #expect(row?.normalised == 0.5)
    }
}
