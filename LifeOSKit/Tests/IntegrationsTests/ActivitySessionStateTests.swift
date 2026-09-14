import Foundation
import Testing
@testable import Integrations

struct ActivitySessionStateTests {
    let start = Date(timeIntervalSince1970: 1_000)
    @Test func backgroundTimeAndPauses() {
        var session = ActivitySessionState(activity: "Walk", at: start)
        #expect(session.elapsed(at: start.addingTimeInterval(3600)) == 3600)
        session.pause(at: start.addingTimeInterval(60))
        session.pause(at: start.addingTimeInterval(100))
        #expect(session.elapsed(at: start.addingTimeInterval(600)) == 60)
        session.resume(at: start.addingTimeInterval(600))
        session.resume(at: start.addingTimeInterval(610))
        session.finish(at: start.addingTimeInterval(630))
        session.resume(at: start.addingTimeInterval(700))
        session.finish(at: start.addingTimeInterval(800))
        #expect(session.elapsed(at: start.addingTimeInterval(900)) == 90)
        #expect(session.endedAt == start.addingTimeInterval(630))
    }
    @Test func restoredSessionRetainsIdentityAndTiming() throws {
        let session = ActivitySessionState(activity: "Run", at: start)
        let restored = try JSONDecoder().decode(ActivitySessionState.self, from: JSONEncoder().encode(session))
        #expect(restored == session)
        #expect(restored.elapsed(at: start.addingTimeInterval(300)) == 300)
        #expect(restored.elapsed(at: start.addingTimeInterval(-30)) == 0)
    }
    @Test func heartRateFrames() {
        #expect(HeartRateMeasurement.beatsPerMinute(Data([0, 72])) == 72)
        #expect(HeartRateMeasurement.beatsPerMinute(Data([1, 200, 0])) == 200)
        #expect(HeartRateMeasurement.beatsPerMinute(Data([6, 88])) == 88)
        #expect(HeartRateMeasurement.beatsPerMinute(Data([4, 88])) == nil)
        for bytes: [UInt8] in [[], [1], [1, 90], [0, 0], [1, 255, 1]] {
            #expect(HeartRateMeasurement.beatsPerMinute(Data(bytes)) == nil)
        }
    }
}
