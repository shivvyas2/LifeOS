import Testing
@testable import DesignSystem

@Suite struct WalkthroughRunTests {
    @Test func startingShowsTheShelfAndTheFirstStep() {
        var run = WalkthroughRun()
        #expect(run.start() == [.showShelf])
        #expect(run.stepIndex == 0)
    }

    @Test func startingAgainWhileRunningChangesNothing() {
        var run = WalkthroughRun()
        _ = run.start()
        _ = run.next()
        #expect(run.start() == [])
        #expect(run.stepIndex == 1)
    }

    @Test func theFirstPageStepOpensTheSampleOnce() {
        var run = WalkthroughRun()
        _ = run.start()
        #expect(run.next() == [.openSample])
        #expect(run.next() == [])
        #expect(run.stepIndex == 2)
    }

    @Test func leavingThePageShowsTheShelf() {
        var run = WalkthroughRun()
        _ = run.start(); _ = run.next(); _ = run.next()
        #expect(run.next() == [.showShelf])
        #expect(run.stepIndex == 3)
    }

    /// The discard comes before the shelf, so the app can flush the open
    /// sample's editor and read what was typed before deciding.
    @Test func finishingAfterTheSampleDiscardsItBeforeShowingTheShelf() {
        var run = WalkthroughRun()
        _ = run.start(); _ = run.next(); _ = run.next()
        #expect(run.skip() == [.discardSample, .showShelf, .markSeen])
        #expect(run.stepIndex == nil)
    }

    @Test func doneOnTheLastStepDiscardsAndMarksSeen() {
        var run = WalkthroughRun()
        _ = run.start(); _ = run.next(); _ = run.next(); _ = run.next(); _ = run.next()
        #expect(run.isLast)
        #expect(run.next() == [.discardSample, .showShelf, .markSeen])
    }

    @Test func skippingBeforeTheSampleOnlyMarksSeen() {
        var run = WalkthroughRun()
        _ = run.start()
        #expect(run.skip() == [.markSeen])
    }

    @Test func aMissingAnchorMovesOnAndStaysSkipped() {
        var run = WalkthroughRun()
        _ = run.start(); _ = run.next(); _ = run.next(); _ = run.next()
        #expect(run.anchorMissing(at: 3) == [])
        #expect(run.stepIndex == 4)
        #expect(run.isLast)
    }

    @Test func aLateTimeoutForAnEarlierStepDoesNothing() {
        var run = WalkthroughRun()
        _ = run.start(); _ = run.next()
        #expect(run.anchorMissing(at: 0) == [])
        #expect(run.stepIndex == 1)
    }

    @Test func theStepBeforeAMissingLastStepIsLast() {
        var run = WalkthroughRun()
        _ = run.start(); _ = run.next(); _ = run.next(); _ = run.next(); _ = run.next()
        _ = run.anchorMissing(at: 4)
        #expect(run.stepIndex == nil)
        _ = run.start(); _ = run.next(); _ = run.next(); _ = run.next()
        #expect(!run.isLast)
    }
}
