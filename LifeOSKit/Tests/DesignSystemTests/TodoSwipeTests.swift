import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodoSwipeTests {
    @Test func aRightwardSwipeOfTheMinimumTicks() {
        #expect(TodoSwipe.ticks(dx: 48, dy: 0))
        #expect(TodoSwipe.ticks(dx: 90, dy: -20))
    }

    @Test func aShortOrLeftwardDragDoesNot() {
        #expect(!TodoSwipe.ticks(dx: 47, dy: 0))
        #expect(!TodoSwipe.ticks(dx: -60, dy: 0))
    }

    @Test func aScrollIsNotATick() {
        #expect(!TodoSwipe.ticks(dx: 50, dy: 80))
        #expect(!TodoSwipe.ticks(dx: 50, dy: -50))
    }
}
