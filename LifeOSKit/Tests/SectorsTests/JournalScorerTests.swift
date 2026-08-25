import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct JournalScorerTests {

    private func dates(_ count: Int) -> [Date] {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        return (0..<count).map {
            Calendar.current.date(byAdding: .day, value: $0, to: start)!
        }
    }

    @Test func writingMostDaysScoresWell() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: dates(24), daysInMonth: 30, previousEntryCount: nil
        )
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! >= 7)
    }

    @Test func aSilentMonthProposesNothing() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: [], daysInMonth: 30, previousEntryCount: nil
        )
        #expect(scorer.evidence().proposedScore == nil)
    }

    @Test func theSectorIsWhicheverWasAskedFor() {
        let mind = JournalScorer(
            sector: .mind, entryDates: dates(5), daysInMonth: 30, previousEntryCount: nil
        )
        #expect(mind.sector == .mind)
    }

    /// Twelve entries on one day is not twelve days of reflection.
    @Test func severalEntriesOnOneDayCountAsOneDay() {
        let sameDay = Array(repeating: dates(1)[0], count: 12)
        let scorer = JournalScorer(
            sector: .soul, entryDates: sameDay, daysInMonth: 30, previousEntryCount: nil
        )
        let row = scorer.evidence().rows.first { $0.label == "days written" }
        #expect(row?.value == "1/30")
    }

    @Test func writingMoreThanLastMonthIsCredited() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: dates(10), daysInMonth: 30, previousEntryCount: 5
        )
        let row = scorer.evidence().rows.first { $0.label == "vs last month" }
        #expect(row != nil)
        #expect(row!.normalised > 0.5)
    }

    @Test func withNoPreviousMonthThereIsNoComparisonRow() {
        let scorer = JournalScorer(
            sector: .soul, entryDates: dates(10), daysInMonth: 30, previousEntryCount: nil
        )
        #expect(!scorer.evidence().rows.contains { $0.label == "vs last month" })
    }
}
