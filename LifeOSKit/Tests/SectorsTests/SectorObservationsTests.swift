import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorObservationsTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func entry(_ m: Int, user: Int, proposed: Int?) -> MonthEntry {
        MonthEntry(
            month: calendar.date(from: DateComponents(year: 2026, month: m, day: 1))!,
            userScore: user, proposedScore: proposed, evidenceRows: []
        )
    }

    private func track(_ answers: [String?]) -> QuestionTrack {
        QuestionTrack(questionID: "friends.seen", prompt: "How often did you see friends?", answers: answers)
    }

    @Test func threeIdenticalAnswersInARowIsWorthSaying() {
        let said = SectorObservations.all(
            months: [], questions: [track(["barely", "barely", "barely"])]
        )
        #expect(said.contains { $0.contains("barely") })
    }

    /// Two is a coincidence. Three is a pattern.
    @Test func twoIdenticalAnswersIsNot() {
        let said = SectorObservations.all(
            months: [], questions: [track(["some", "barely", "barely"])]
        )
        #expect(said.isEmpty)
    }

    @Test func aGapInTheRunBreaksIt() {
        let said = SectorObservations.all(
            months: [], questions: [track(["barely", nil, "barely", "barely"])]
        )
        #expect(said.isEmpty)
    }

    /// The signal the spine kept two score columns to preserve.
    @Test func scoringBelowTheProposalThreeMonthsRunningIsWorthSaying() {
        let said = SectorObservations.all(
            months: [entry(6, user: 4, proposed: 7),
                     entry(7, user: 5, proposed: 8),
                     entry(8, user: 4, proposed: 6)],
            questions: []
        )
        #expect(said.contains { $0.lowercased().contains("lower") })
    }

    @Test func aSingleMonthBelowTheProposalIsNot() {
        let said = SectorObservations.all(
            months: [entry(6, user: 7, proposed: 7),
                     entry(7, user: 8, proposed: 8),
                     entry(8, user: 4, proposed: 6)],
            questions: []
        )
        #expect(said.isEmpty)
    }

    /// A month the rule could not propose for cannot be part of a gap run.
    @Test func aMonthWithNoProposalBreaksTheGapRun() {
        let said = SectorObservations.all(
            months: [entry(6, user: 4, proposed: 7),
                     entry(7, user: 5, proposed: nil),
                     entry(8, user: 4, proposed: 6)],
            questions: []
        )
        #expect(said.isEmpty)
    }

    @Test func scoringAboveTheProposalSaysNothing() {
        let said = SectorObservations.all(
            months: [entry(6, user: 9, proposed: 7),
                     entry(7, user: 9, proposed: 8),
                     entry(8, user: 8, proposed: 6)],
            questions: []
        )
        #expect(said.isEmpty)
    }
}
