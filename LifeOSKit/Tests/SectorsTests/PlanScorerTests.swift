import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct MissionScorerTests {

    @Test func everythingDoneScoresAtTheTop() {
        let scorer = MissionScorer(
            statuses: Array(repeating: .done, count: 5), habitTickRate: 1.0
        )
        #expect(scorer.evidence().proposedScore == 10)
        #expect(scorer.sector == .mission)
    }

    @Test func nothingMovedScoresAtTheBottom() {
        let scorer = MissionScorer(
            statuses: Array(repeating: .todo, count: 5), habitTickRate: 0
        )
        #expect(scorer.evidence().proposedScore == 0)
    }

    /// In progress is movement, not completion, and is worth part credit.
    @Test func inProgressCountsForSomethingButNotEverything() {
        let all = MissionScorer(statuses: Array(repeating: .inProgress, count: 4), habitTickRate: nil)
        let score = all.evidence().proposedScore
        #expect(score != nil)
        #expect(score! > 0 && score! < 10)
    }

    /// Blocked is not the person's failure and must not be scored as a miss.
    @Test func blockedItemsAreExcludedFromJudgement() {
        let mixed = MissionScorer(statuses: [.done, .done, .blocked, .blocked], habitTickRate: nil)
        #expect(mixed.evidence().proposedScore == 10)
    }

    @Test func noEntriesProposesNothing() {
        #expect(MissionScorer(statuses: [], habitTickRate: nil).evidence().proposedScore == nil)
    }

    @Test func onlyBlockedEntriesProposeNothing() {
        let scorer = MissionScorer(statuses: [.blocked, .blocked], habitTickRate: nil)
        #expect(scorer.evidence().proposedScore == nil)
    }

    @Test func aMissingHabitRateAddsNoRow() {
        let scorer = MissionScorer(statuses: [.done], habitTickRate: nil)
        #expect(!scorer.evidence().rows.contains { $0.label == "habits kept" })
    }
}

@Suite struct GrowthScorerTests {

    @Test func metTargetsAndFinishedGoalsScoreAtTheTop() {
        let scorer = GrowthScorer(goalStatuses: [.done, .done], targetsMet: 4, targetsTotal: 4)
        #expect(scorer.evidence().proposedScore == 10)
        #expect(scorer.sector == .growth)
    }

    @Test func halfTheTargetsScoresInTheMiddle() {
        let scorer = GrowthScorer(goalStatuses: [], targetsMet: 2, targetsTotal: 4)
        #expect(scorer.evidence().proposedScore == 5)
    }

    @Test func noGoalsAndNoTargetsProposesNothing() {
        let scorer = GrowthScorer(goalStatuses: [], targetsMet: 0, targetsTotal: 0)
        #expect(scorer.evidence().proposedScore == nil)
    }

    @Test func theEvidenceNamesTheTargetCount() {
        let scorer = GrowthScorer(goalStatuses: [], targetsMet: 3, targetsTotal: 4)
        let row = scorer.evidence().rows.first { $0.label == "targets met" }
        #expect(row?.value == "3/4")
    }

    @Test func noTargetsSetAddsNoRow() {
        let scorer = GrowthScorer(goalStatuses: [.done], targetsMet: 0, targetsTotal: 0)
        #expect(!scorer.evidence().rows.contains { $0.label == "targets met" })
    }
}
