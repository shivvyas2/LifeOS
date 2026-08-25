import Testing
import Persistence
@testable import Sectors

@Suite struct NoteRequestTests {

    // MARK: - shouldRequest

    /// The bug this guards against: a note requested on `.task(id: sector)`
    /// fires while evidence is still empty for a check-in sector, so the
    /// note request must instead fire on this transition.
    @Test func emptyToNonEmptyTriggersARequest() {
        #expect(NoteRequest.shouldRequest(wasEmpty: true, isEmptyNow: false))
    }

    @Test func alreadyNonEmptyDoesNotRetrigger() {
        #expect(!NoteRequest.shouldRequest(wasEmpty: false, isEmptyNow: false))
    }

    @Test func stayingEmptyDoesNotTrigger() {
        #expect(!NoteRequest.shouldRequest(wasEmpty: true, isEmptyNow: true))
    }

    @Test func nonEmptyToEmptyDoesNotTrigger() {
        #expect(!NoteRequest.shouldRequest(wasEmpty: false, isEmptyNow: true))
    }

    // MARK: - shouldApply

    /// The bug this guards against: the close advances to a new sector while
    /// a note request for the old one is still in flight, and the old note
    /// resolves after the sector already changed.
    @Test func aStaleResultForTheOldSectorIsRejected() {
        #expect(!NoteRequest.shouldApply(resultSector: .soul, currentSector: .mind))
    }

    @Test func aResultMatchingTheCurrentSectorIsApplied() {
        #expect(NoteRequest.shouldApply(resultSector: .soul, currentSector: .soul))
    }

    @Test func aResultArrivingAfterTheCloseFinishedIsRejected() {
        #expect(!NoteRequest.shouldApply(resultSector: .soul, currentSector: nil))
    }
}
