import Testing
@testable import Motion

struct RallyEndDetectorTests {
    @Test func aRallyGoingQuietIsAskedAboutOnce() {
        var detector = RallyEndDetector()
        detector.swing(at: 10); detector.swing(at: 11.5); detector.swing(at: 13)
        do { let asked = detector.shouldAsk(at: 15); #expect(!asked) }
        do { let asked = detector.shouldAsk(at: 17.1); #expect(asked) }
        do { let asked = detector.shouldAsk(at: 20); #expect(!asked) }
    }

    @Test func nothingIsAskedBeforeAnySwing() {
        var detector = RallyEndDetector()
        do { let asked = detector.shouldAsk(at: 100); #expect(!asked) }
    }

    @Test func scoringClosesTheRallySoItIsNotAskedAgain() {
        var detector = RallyEndDetector()
        detector.swing(at: 10)
        detector.scored()
        do { let asked = detector.shouldAsk(at: 30); #expect(!asked) }
    }

    @Test func aNewSwingAfterAskingStartsTheNextRally() {
        var detector = RallyEndDetector()
        detector.swing(at: 10)
        do { let asked = detector.shouldAsk(at: 15); #expect(asked) }
        detector.swing(at: 30)
        do { let asked = detector.shouldAsk(at: 32); #expect(!asked) }
        do { let asked = detector.shouldAsk(at: 34.5); #expect(asked) }
    }

    @Test func aPauseNeverBecomesAPrompt() {
        var detector = RallyEndDetector()
        detector.swing(at: 10)
        detector.interrupt()
        do { let asked = detector.shouldAsk(at: 60); #expect(!asked) }
    }
}
