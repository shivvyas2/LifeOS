import Testing
@testable import Sectors

@Suite struct ChosenScoreTests {

    /// The bug this guards against: the person moves the stepper to 9, then
    /// types into an unrelated free-text field. That answer triggers a
    /// recompute, and the recompute must not revert their 9.
    @Test func aChosenScoreSurvivesARecomputeTriggeredByAnotherAnswer() {
        let seeded = ChosenScore.seeded(
            current: 9, hasChosen: true, proposed: 7, previousUserScore: 7
        )
        #expect(seeded == 9)
    }

    @Test func beforeAnyChoiceTheSeedTracksTheProposal() {
        let seeded = ChosenScore.seeded(
            current: 5, hasChosen: false, proposed: 8, previousUserScore: 6
        )
        #expect(seeded == 8)
    }

    @Test func withNoProposalTheSeedFallsBackToLastMonth() {
        let seeded = ChosenScore.seeded(
            current: 5, hasChosen: false, proposed: nil, previousUserScore: 6
        )
        #expect(seeded == 6)
    }

    @Test func withNeitherProposalNorHistoryTheSeedIsFive() {
        let seeded = ChosenScore.seeded(
            current: 5, hasChosen: false, proposed: nil, previousUserScore: nil
        )
        #expect(seeded == 5)
    }

    /// A sector with thin data proposes nothing at first; answering a
    /// check-in question should still move the seed even though the person
    /// has not touched the stepper.
    @Test func answeringAQuestionBeforeTouchingTheStepperUpdatesTheSeed() {
        let beforeAnswering = ChosenScore.seeded(
            current: 5, hasChosen: false, proposed: nil, previousUserScore: nil
        )
        #expect(beforeAnswering == 5)

        let afterAnswering = ChosenScore.seeded(
            current: beforeAnswering, hasChosen: false, proposed: 4, previousUserScore: nil
        )
        #expect(afterAnswering == 4)
    }
}
