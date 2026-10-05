import Testing
import Foundation
@testable import Sectors

@Suite struct CloseScheduleTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func month(_ year: Int, _ month: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private var previousMonth: Date { month(2026, 8) }

    /// A fresh install has no `SectorScore` rows at all, so `scoredCounts` is
    /// empty. Without the fallback this would leave the board silent
    /// forever: rows are only created by a close, and a close is only
    /// offered once a row already exists.
    @Test func freshInstallOffersThePreviousMonth() {
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [:],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 0,
            totalSectors: 9,
            calendar: calendar
        )
        #expect(offered == previousMonth)
    }

    @Test func aFullyScoredPreviousMonthWithNoOlderGapOffersNothing() {
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [previousMonth: 9],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9,
            totalSectors: 9,
            calendar: calendar
        )
        #expect(offered == nil)
    }

    /// A gap two months back must not be buried under a more recent, still
    /// partially open month: the oldest gap in the window wins.
    @Test func aGapTwoMonthsBackIsOfferedBeforeThePreviousMonth() {
        let twoMonthsBack = month(2026, 6)
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [twoMonthsBack: 3, previousMonth: 5],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 5,
            totalSectors: 9,
            calendar: calendar
        )
        #expect(offered == twoMonthsBack)
    }

    /// A month with all nine sectors scored is not a gap, even though it has
    /// rows and even though it is older than another candidate.
    @Test func aFullyScoredMonthIsSkipped() {
        let fullyScored = month(2026, 6)
        let stillOpen = month(2026, 7)
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [fullyScored: 9, stillOpen: 4],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9,
            totalSectors: 9,
            calendar: calendar
        )
        #expect(offered == stillOpen)
    }

    /// A gap older than the look-back is never offered, however real it is:
    /// unbounded, one ancient partial month would pin the banner forever.
    @Test func nothingOlderThanTheLookBackIsOffered() {
        let farBack = month(2024, 1)
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [farBack: 2],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9,
            totalSectors: 9,
            lookbackMonths: 12,
            calendar: calendar
        )
        #expect(offered == nil)
    }

    @Test func aPartiallyScoredPreviousMonthIsStillOffered() {
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [previousMonth: 4],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 4,
            totalSectors: 9,
            calendar: calendar
        )
        #expect(offered == previousMonth)
    }

    @Test func defaultTotalSectorsMatchesTheBoard() {
        let offered = CloseSchedule.monthAwaitingClose(
            scoredCounts: [:],
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9,
            calendar: calendar
        )
        #expect(offered == nil)
    }

    // MARK: - Last closed month

    /// A skipped month must not erase the ones before it: the board names the
    /// newest month that has any score, not only the month just gone.
    @Test func lastClosedMonthIsTheNewestWithAScore() {
        let counts = [month(2026, 7): 9, month(2026, 8): 9, month(2026, 9): 0]
        #expect(CloseSchedule.lastClosedMonth(scoredCounts: counts) == month(2026, 8))
    }

    @Test func lastClosedMonthIsNilWhenNothingWasEverScored() {
        #expect(CloseSchedule.lastClosedMonth(scoredCounts: [:]) == nil)
        #expect(CloseSchedule.lastClosedMonth(scoredCounts: [month(2026, 9): 0]) == nil)
    }
}
