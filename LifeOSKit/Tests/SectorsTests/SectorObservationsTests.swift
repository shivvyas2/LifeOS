import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorObservationsTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func entry(year: Int = 2026, _ m: Int, user: Int, proposed: Int?) -> MonthEntry {
        MonthEntry(
            month: calendar.date(from: DateComponents(year: year, month: m, day: 1))!,
            userScore: user, proposedScore: proposed, evidenceRows: []
        )
    }

    private func track(_ answers: [String?]) -> QuestionTrack {
        QuestionTrack(questionID: "friends.seen", prompt: "How often did you see friends?", answers: answers)
    }

    /// Three calendar-adjacent months, matching the length and order of the
    /// three-answer tracks the repeated-answer tests exercise.
    private var consecutiveMonths: [MonthEntry] {
        [entry(6, user: 5, proposed: nil), entry(7, user: 5, proposed: nil), entry(8, user: 5, proposed: nil)]
    }

    @Test func threeIdenticalAnswersInARowIsWorthSaying() {
        let said = SectorObservations.all(
            months: consecutiveMonths, questions: [track(["barely", "barely", "barely"])], calendar: calendar
        )
        #expect(said.contains { $0.contains("barely") })
    }

    /// Two is a coincidence. Three is a pattern.
    @Test func twoIdenticalAnswersIsNot() {
        let said = SectorObservations.all(
            months: consecutiveMonths, questions: [track(["some", "barely", "barely"])], calendar: calendar
        )
        #expect(said.isEmpty)
    }

    @Test func aGapInTheRunBreaksIt() {
        let months = [entry(5, user: 5, proposed: nil), entry(6, user: 5, proposed: nil),
                      entry(7, user: 5, proposed: nil), entry(8, user: 5, proposed: nil)]
        let said = SectorObservations.all(
            months: months, questions: [track(["barely", nil, "barely", "barely"])], calendar: calendar
        )
        #expect(said.isEmpty)
    }

    /// The signal the spine kept two score columns to preserve.
    @Test func scoringBelowTheProposalThreeMonthsRunningIsWorthSaying() {
        let said = SectorObservations.all(
            months: [entry(6, user: 4, proposed: 7),
                     entry(7, user: 5, proposed: 8),
                     entry(8, user: 4, proposed: 6)],
            questions: [], calendar: calendar
        )
        #expect(said.contains { $0.lowercased().contains("lower") })
    }

    @Test func aSingleMonthBelowTheProposalIsNot() {
        let said = SectorObservations.all(
            months: [entry(6, user: 7, proposed: 7),
                     entry(7, user: 8, proposed: 8),
                     entry(8, user: 4, proposed: 6)],
            questions: [], calendar: calendar
        )
        #expect(said.isEmpty)
    }

    /// A month the rule could not propose for cannot be part of a gap run.
    @Test func aMonthWithNoProposalBreaksTheGapRun() {
        let said = SectorObservations.all(
            months: [entry(6, user: 4, proposed: 7),
                     entry(7, user: 5, proposed: nil),
                     entry(8, user: 4, proposed: 6)],
            questions: [], calendar: calendar
        )
        #expect(said.isEmpty)
    }

    @Test func scoringAboveTheProposalSaysNothing() {
        let said = SectorObservations.all(
            months: [entry(6, user: 9, proposed: 7),
                     entry(7, user: 9, proposed: 8),
                     entry(8, user: 8, proposed: 6)],
            questions: [], calendar: calendar
        )
        #expect(said.isEmpty)
    }

    // MARK: - Consecutive-months gate (FIX 2)

    /// `SectorStore.history` only keeps scored months, so a partial close
    /// that skips a sector one month is the ordinary shape of a partial
    /// close, not a rare failure state. Jun, Jul, Sep are the last three
    /// *entries*, but they are not three months running, for either rule.
    @Test func skippingAMonthIsNotThreeMonthsRunningForEitherRule() {
        let months = [entry(6, user: 4, proposed: 7), entry(7, user: 4, proposed: 7), entry(9, user: 4, proposed: 7)]
        let said = SectorObservations.all(
            months: months, questions: [track(["barely", "barely", "barely"])], calendar: calendar
        )
        #expect(said.isEmpty)
    }

    /// The mirror of the above: three genuinely adjacent months still fire,
    /// for both rules at once.
    @Test func threeAdjacentMonthsStillFireBothRules() {
        let months = [entry(6, user: 4, proposed: 7), entry(7, user: 4, proposed: 7), entry(8, user: 4, proposed: 7)]
        let said = SectorObservations.all(
            months: months, questions: [track(["barely", "barely", "barely"])], calendar: calendar
        )
        #expect(said.contains { $0.contains("barely") })
        #expect(said.contains { $0.lowercased().contains("lower") })
    }

    /// December rolling into January is adjacent despite the year change.
    @Test func decemberToJanuaryIsConsecutiveAcrossTheYearBoundary() {
        let months = [entry(year: 2025, 11, user: 4, proposed: 7),
                      entry(year: 2025, 12, user: 4, proposed: 7),
                      entry(year: 2026, 1, user: 4, proposed: 7)]
        let said = SectorObservations.all(months: months, questions: [], calendar: calendar)
        #expect(said.contains { $0.lowercased().contains("lower") })
    }
}
