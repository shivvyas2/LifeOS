import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BoardHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var october: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 1))!
    }
    private var september: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    @Test func closedNamesTheMonthAndBothBoardFacts() {
        let summary = BoardSummary(scores: [.body: 8, .friends: 3], previous: [.body: 6, .friends: 3])
        let headline = BoardHeadline.closed(month: october, lastClosed: september, summary: summary, locale: en)
        #expect(headline.eyebrow == "Life · October")
        #expect(headline.title == "September closed")
        #expect(headline.detail == "Lowest: Friends · Biggest move: Body +2")
    }

    @Test func closedWithNothingSaysSo() {
        let headline = BoardHeadline.closed(month: october, lastClosed: nil,
                                            summary: BoardSummary(scores: [:], previous: [:]), locale: en)
        #expect(headline.title == "Nothing closed yet")
        #expect(headline.detail == nil)
    }

    @Test func closedOmitsAFactThatHasNoValue() {
        let summary = BoardSummary(scores: [.body: 8], previous: [:])
        let headline = BoardHeadline.closed(month: october, lastClosed: september, summary: summary, locale: en)
        #expect(headline.detail == "Lowest: Body")
    }

    @Test func inFlightCountsDownAndReportsDecided() {
        let headline = BoardHeadline.inFlight(month: october, remainingDays: 18, meanDecided: 0.624, locale: en)
        #expect(headline.eyebrow == "Life · October")
        #expect(headline.title == "18 days left")
        #expect(headline.detail == "62% of this month is decided")
    }

    @Test func oneDayLeftIsSingular() {
        let headline = BoardHeadline.inFlight(month: october, remainingDays: 1, meanDecided: nil, locale: en)
        #expect(headline.title == "1 day left")
        #expect(headline.detail == nil)
    }
}
