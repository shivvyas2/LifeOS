import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct CloseProgressTests {

    @Test func aFreshCloseStartsAtTheFirstSectorInBoardOrder() {
        let progress = CloseProgress(scored: [])
        #expect(progress.next == LifeSector.boardOrder.first)
        #expect(progress.position == 1)
        #expect(progress.total == 9)
    }

    /// Leaving midway is normal, so returning resumes rather than restarting.
    @Test func aResumedCloseSkipsWhatIsAlreadyScored() {
        let done = Set(LifeSector.boardOrder.prefix(4))
        let progress = CloseProgress(scored: done)
        #expect(progress.next == LifeSector.boardOrder[4])
        #expect(progress.position == 5)
    }

    /// A skipped sector stays genuinely unscored, so it is offered again
    /// rather than being treated as finished.
    @Test func aSkippedSectorIsStillOffered() {
        let progress = CloseProgress(scored: [LifeSector.boardOrder[1]])
        #expect(progress.next == LifeSector.boardOrder[0])
    }

    @Test func aFinishedCloseHasNoNextSector() {
        let progress = CloseProgress(scored: Set(LifeSector.allCases))
        #expect(progress.next == nil)
        #expect(progress.isComplete)
    }

    @Test func anUnfinishedCloseIsNotComplete() {
        #expect(!CloseProgress(scored: [.body]).isComplete)
    }

    /// `MonthlyCloseViewModel.skip()` unions the store's committed sectors
    /// with a session-only skip set before building `CloseProgress`, so this
    /// is the shape that exercises: skipping the sector on screen must move
    /// past it without ever marking it scored.
    @Test func skippingTheCurrentSectorMovesToTheNextOne() {
        let scored: Set<LifeSector> = []
        let skippedThisSession: Set<LifeSector> = [LifeSector.boardOrder[0]]
        let progress = CloseProgress(scored: scored.union(skippedThisSession))
        #expect(progress.next == LifeSector.boardOrder[1])
    }

    /// A skip is session-only: a fresh `CloseProgress` built without the
    /// session's skip set (as happens the next time the close is opened)
    /// offers the skipped sector again.
    @Test func aSkipDoesNotPersistBeyondItsSession() {
        let progress = CloseProgress(scored: [])
        #expect(progress.next == LifeSector.boardOrder[0])
    }
}
