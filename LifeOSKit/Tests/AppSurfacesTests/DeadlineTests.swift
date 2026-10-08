import Testing
import Foundation
@testable import AppSurfaces

@Suite struct DeadlineTests {
    @Test func aFastAnswerArrives() async {
        let value = await firstValue(within: .seconds(2)) { 7 }
        #expect(value == 7)
    }

    @Test func aSlowAnswerIsNotWaitedFor() async {
        let clock = ContinuousClock()
        let began = clock.now
        // The operation ignores cancellation, like a location fix does.
        let value: Int? = await firstValue(within: .milliseconds(200)) {
            await withCheckedContinuation { c in
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { c.resume(returning: 1) }
            }
        }
        #expect(value == nil)
        #expect(began.duration(to: clock.now) < .seconds(1))
    }
}

@Suite struct FocusCommandGateTests {
    @Test func aFocusSessionTakesOnlyDiscard() {
        #expect(WatchWire.phoneMayDrive(.discard, focusSession: true))
        for command in [PhoneCommand.end, .pause, .resume, .configure, .nextSet] {
            #expect(!WatchWire.phoneMayDrive(command, focusSession: true))
            #expect(WatchWire.phoneMayDrive(command, focusSession: false))
        }
    }
}
