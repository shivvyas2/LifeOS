import Testing
import Foundation
@testable import Sectors

@Suite struct CloseScheduleTests {
    private let previousMonth = Date(timeIntervalSince1970: 1_700_000_000)
    private let olderMonth = Date(timeIntervalSince1970: 1_690_000_000)

    /// A fresh install has no `SectorScore` rows at all, so the store's query
    /// for the oldest unclosed month returns nil. Without the fallback this
    /// would leave the board silent forever: rows are only created by a
    /// close, and a close is only offered once a row already exists.
    @Test func freshInstallOffersThePreviousMonth() {
        let month = CloseSchedule.monthAwaitingClose(
            oldestUnclosed: nil,
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 0,
            totalSectors: 9
        )
        #expect(month == previousMonth)
    }

    @Test func aFullyScoredPreviousMonthWithNoOlderGapOffersNothing() {
        let month = CloseSchedule.monthAwaitingClose(
            oldestUnclosed: nil,
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9,
            totalSectors: 9
        )
        #expect(month == nil)
    }

    /// An older gap must not be buried under a more recent, still-open month.
    @Test func anOlderUnclosedMonthTakesPrecedence() {
        let month = CloseSchedule.monthAwaitingClose(
            oldestUnclosed: olderMonth,
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9,
            totalSectors: 9
        )
        #expect(month == olderMonth)
    }

    @Test func aPartiallyScoredPreviousMonthIsStillOffered() {
        let month = CloseSchedule.monthAwaitingClose(
            oldestUnclosed: nil,
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 4,
            totalSectors: 9
        )
        #expect(month == previousMonth)
    }

    @Test func defaultTotalSectorsMatchesTheBoard() {
        let month = CloseSchedule.monthAwaitingClose(
            oldestUnclosed: nil,
            previousMonth: previousMonth,
            scoredSectorsInPreviousMonth: 9
        )
        #expect(month == nil)
    }
}
