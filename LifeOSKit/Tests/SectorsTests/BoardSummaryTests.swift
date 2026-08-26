import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BoardSummaryTests {

    @Test func theLowestSectorIsFound() {
        let summary = BoardSummary(
            scores: [.body: 8, .friends: 3, .money: 6], previous: [:]
        )
        #expect(summary.lowest == .friends)
    }

    @Test func anEmptyBoardHasNoLowest() {
        #expect(BoardSummary(scores: [:], previous: [:]).lowest == nil)
    }

    @Test func theBiggestMoverIsFound() {
        let summary = BoardSummary(
            scores: [.body: 8, .friends: 3], previous: [.body: 7, .friends: 8]
        )
        #expect(summary.biggestMover?.sector == .friends)
        #expect(summary.biggestMover?.delta == -5)
    }

    /// A first month has nothing to compare against and must not claim a move.
    @Test func withNoPreviousMonthThereIsNoMover() {
        let summary = BoardSummary(scores: [.body: 8], previous: [:])
        #expect(summary.biggestMover == nil)
    }

    @Test func aSectorMissingLastMonthIsNotAMover() {
        let summary = BoardSummary(
            scores: [.body: 8, .romance: 9], previous: [.body: 8]
        )
        #expect(summary.biggestMover == nil)
    }

    /// A drop and a rise of equal size: the drop is the one worth surfacing.
    @Test func tiesGoToTheDrop() {
        let summary = BoardSummary(
            scores: [.body: 9, .friends: 3], previous: [.body: 6, .friends: 6]
        )
        #expect(summary.biggestMover?.sector == .friends)
    }
}
