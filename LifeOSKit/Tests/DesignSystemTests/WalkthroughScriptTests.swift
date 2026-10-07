import Testing
import Foundation
@testable import DesignSystem

@Suite struct WalkthroughScriptTests {
    private let all = Set(WalkthroughAnchor.allCases)

    @Test func fiveStepsInOrder() {
        #expect(WalkthroughScript.notes.map(\.anchor) == [.notesNew, .notesFileChip, .notesBlockPicker, .notesTodos, .notesLibrary])
        #expect(WalkthroughScript.notes[0].sentence == "One tap starts a page. It lands in your Inbox until you file it.")
        #expect(WalkthroughScript.notes[4].sentence == "Folders, favourites and habits live here.")
    }

    @Test func itStartsAtTheFirstAndWalksOn() {
        #expect(WalkthroughScript.next(after: nil, available: all) == 0)
        #expect(WalkthroughScript.next(after: 0, available: all) == 1)
        #expect(WalkthroughScript.next(after: 3, available: all) == 4)
    }

    @Test func aMissingAnchorIsSkipped() {
        let noChip = all.subtracting([.notesFileChip])
        #expect(WalkthroughScript.next(after: 0, available: noChip) == 2)
    }

    @Test func nothingIsLeftWhenTheRestAreMissing() {
        #expect(WalkthroughScript.next(after: 4, available: all) == nil)
        #expect(WalkthroughScript.next(after: 2, available: [.notesNew]) == nil)
    }

    @Test func theLastAvailableStepIsLast() {
        #expect(WalkthroughScript.isLast(4, available: all))
        #expect(!WalkthroughScript.isLast(3, available: all))
        #expect(WalkthroughScript.isLast(3, available: all.subtracting([.notesLibrary])))
    }

    @Test func theCardSitsAwayFromTheCutOut() {
        #expect(WalkthroughScript.cardSitsBelow(CGRect(x: 300, y: 60, width: 60, height: 32), in: 800))
        #expect(!WalkthroughScript.cardSitsBelow(CGRect(x: 0, y: 700, width: 390, height: 44), in: 800))
    }
}
