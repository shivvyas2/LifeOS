import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct SectorHistoryTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func month(_ m: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: 1))!
    }

    private func score(_ m: Int, user: Int?, proposed: Int? = nil,
                       rows: [EvidenceRow] = []) -> ScoreRecord {
        ScoreRecord(month: month(m), userScore: user, proposedScore: proposed, evidenceRows: rows)
    }

    @Test func monthsAreOrderedOldestFirst() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(8, user: 4), score(6, user: 7), score(7, user: 6)],
            answers: [], calendar: calendar
        )
        #expect(history.months.map(\.userScore) == [7, 6, 4])
    }

    /// A month recorded but never decided is not history yet.
    @Test func onlyDecidedMonthsAppear() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(7, user: nil)],
            answers: [], calendar: calendar
        )
        #expect(history.months.count == 1)
        #expect(history.months.first?.userScore == 7)
    }

    @Test func aSectorWithNothingProducesEmptyBandsNotNil() {
        let history = SectorHistory.build(
            sector: .romance, months: [], answers: [], calendar: calendar
        )
        #expect(history.months.isEmpty)
        #expect(history.questions.isEmpty)
        #expect(history.notes.isEmpty)
        #expect(history.observations.isEmpty)
    }

    /// The archive is the source. Recomputing history is history that lies.
    @Test func evidenceRowsComeFromTheArchive() {
        let archived = EvidenceRow(label: "days written", value: "5/30", normalised: 0.16)
        let history = SectorHistory.build(
            sector: .soul,
            months: [score(8, user: 6, rows: [archived])],
            answers: [], calendar: calendar
        )
        #expect(history.months.first?.evidenceRows == [archived])
    }

    @Test func answersAreGroupedByQuestionInAskedOrder() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(7, user: 6)],
            answers: [
                AnswerRecord(month: month(6), questionID: "friends.seen", answer: "some"),
                AnswerRecord(month: month(7), questionID: "friends.seen", answer: "barely"),
                AnswerRecord(month: month(6), questionID: "friends.depth", answer: "once"),
            ],
            calendar: calendar
        )
        let ids = history.questions.map(\.questionID)
        #expect(ids == ["friends.seen", "friends.depth"])
    }

    /// A month with no answer must leave a gap, not shift later answers left.
    @Test func aMissingAnswerLeavesAGapRatherThanShifting() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(7, user: 6), score(8, user: 4)],
            answers: [
                AnswerRecord(month: month(6), questionID: "friends.seen", answer: "some"),
                AnswerRecord(month: month(8), questionID: "friends.seen", answer: "barely"),
            ],
            calendar: calendar
        )
        let track = history.questions.first { $0.questionID == "friends.seen" }
        #expect(track?.answers == ["some", nil, "barely"])
    }

    /// Free text is a note, not a comparable answer track.
    @Test func freeTextBecomesANoteNotAQuestionTrack() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(8, user: 4)],
            answers: [AnswerRecord(month: month(8), questionID: "friends.note", answer: "call Ravi")],
            calendar: calendar
        )
        #expect(history.questions.contains { $0.questionID == "friends.note" } == false)
        #expect(history.notes.map(\.text) == ["call Ravi"])
    }

    @Test func notesAreNewestFirst() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(6, user: 7), score(8, user: 4)],
            answers: [
                AnswerRecord(month: month(6), questionID: "friends.note", answer: "older"),
                AnswerRecord(month: month(8), questionID: "friends.note", answer: "newer"),
            ],
            calendar: calendar
        )
        #expect(history.notes.map(\.text) == ["newer", "older"])
    }

    /// An answer to a question that has since been removed must not crash or
    /// invent a track with no prompt.
    @Test func anAnswerToAnUnknownQuestionIsDropped() {
        let history = SectorHistory.build(
            sector: .friends,
            months: [score(8, user: 4)],
            answers: [AnswerRecord(month: month(8), questionID: "friends.gone", answer: "x")],
            calendar: calendar
        )
        #expect(history.questions.isEmpty)
        #expect(history.notes.isEmpty)
    }
}
