import Foundation
import Testing
@testable import Integrations

struct WatchClockTests {
    @Test func reconnectRemovesTimePausedWhilePhoneWasAway() {
        let start = Date(timeIntervalSince1970: 1800000000)
        var timer = ActivitySessionState(activity: "Run", at: start)
        timer.synchronize(elapsed: 300, paused: true, at: start.addingTimeInterval(600))
        #expect(timer.elapsed(at: start.addingTimeInterval(900)) == 300)
        timer.synchronize(elapsed: 310, paused: false, at: start.addingTimeInterval(910))
        #expect(timer.elapsed(at: start.addingTimeInterval(920)) == 320)
        timer.finish(at: start.addingTimeInterval(920))
        timer.synchronize(elapsed: 500, paused: false, at: start.addingTimeInterval(930))
        #expect(timer.elapsed() == 320)
    }
    @Test func invalidClockDoesNotPoisonTimer() {
        let start = Date(timeIntervalSince1970: 1800000000)
        var timer = ActivitySessionState(activity: "Run", at: start)
        timer.synchronize(elapsed: .nan, paused: true, at: start)
        timer.synchronize(elapsed: -1, paused: true, at: start)
        #expect(timer.elapsed(at: start.addingTimeInterval(10)) == 10)
    }
}
