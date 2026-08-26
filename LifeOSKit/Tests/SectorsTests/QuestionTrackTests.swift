import Testing
@testable import Sectors

/// `hasAnswer(inLastMonths:)` is what keeps the answers band honest: a track
/// can qualify for `SectorHistory.questions` on an answer from any of the
/// twelve fetched months, but the screen only ever renders the most recent
/// six, so the two must agree on what "has data" means.
@Suite struct QuestionTrackTests {

    private func track(_ answers: [String?]) -> QuestionTrack {
        QuestionTrack(questionID: "friends.seen", prompt: "How often did you see friends?", answers: answers)
    }

    @Test func anAnswerInsideTheWindowCounts() {
        let recent = track([nil, nil, nil, nil, nil, nil, "some"])
        #expect(recent.hasAnswer(inLastMonths: 6))
    }

    @Test func anAnswerOnlyOutsideTheWindowDoesNotCount() {
        let stale = track(["some", nil, nil, nil, nil, nil, nil])
        #expect(!stale.hasAnswer(inLastMonths: 6))
    }

    @Test func noAnswersAtAllDoesNotCount() {
        let empty = track([nil, nil, nil, nil, nil, nil])
        #expect(!empty.hasAnswer(inLastMonths: 6))
    }

    @Test func fewerMonthsThanTheWindowStillChecksWhatExists() {
        let short = track([nil, "barely"])
        #expect(short.hasAnswer(inLastMonths: 6))
    }
}
