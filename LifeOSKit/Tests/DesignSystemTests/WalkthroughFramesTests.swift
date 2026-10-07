import Testing
import Foundation
@testable import DesignSystem

@Suite @MainActor struct WalkthroughFramesTests {
    @Test func aReportedFrameIsAvailable() {
        let frames = WalkthroughFrames()
        frames.report(.notesNew, CGRect(x: 10, y: 10, width: 60, height: 30))
        #expect(frames.available == [.notesNew])
    }

    @Test func aViewThatGoesTakesItsFrame() {
        let frames = WalkthroughFrames()
        frames.report(.notesFileChip, CGRect(x: 10, y: 10, width: 60, height: 30))
        frames.report(.notesFileChip, nil)
        #expect(frames.available.isEmpty)
    }

    @Test func anEmptyFrameIsNotAPlace() {
        let frames = WalkthroughFrames()
        frames.report(.notesTodos, .zero)
        #expect(frames.frames[.notesTodos] == nil)
    }
}
