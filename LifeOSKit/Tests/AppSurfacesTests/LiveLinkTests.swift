import Foundation
import Testing
@testable import AppSurfaces

struct LiveLinkTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func watch(_ packetAge: TimeInterval?, reachable: Bool = true, paused: Bool = false) -> LiveLink {
        LiveLink.assess(watchOwned: true, watchReachable: reachable, lastWatchPacket: packetAge.map { now.addingTimeInterval(-$0) },
                        sensorName: nil, lastHeartRate: nil, paused: paused, now: now)
    }

    @Test func aRecentWatchPacketIsLive() {
        #expect(watch(3) == .watchLive)
        #expect(watch(3).isLive)
    }

    @Test func aWatchThatStopsSendingGoesQuietThenSaysHowLong() {
        #expect(watch(40) == .watchQuiet(seconds: 40))
        #expect(watch(40).title == "Apple Watch · last reading 40 s ago")
        #expect(watch(150).title == "Apple Watch · last reading 2 min ago")
        #expect(!watch(40).isLive)
        #expect(watch(nil).title == "Apple Watch · waiting for the first reading")
    }

    @Test func aDroppedSessionIsDisconnectedWhateverTheLastPacket() {
        #expect(watch(1, reachable: false) == .watchDisconnected)
    }

    @Test func pausedOverridesFreshness() {
        #expect(watch(500, paused: true) == .paused)
    }

    @Test func thePhoneReportsItsStrapOrItsAbsence() {
        let live = LiveLink.assess(watchOwned: false, watchReachable: false, lastWatchPacket: nil,
                                   sensorName: "WHOOP", lastHeartRate: now.addingTimeInterval(-2), paused: false, now: now)
        #expect(live == .sensorLive(name: "WHOOP"))
        let quiet = LiveLink.assess(watchOwned: false, watchReachable: false, lastWatchPacket: nil,
                                    sensorName: "WHOOP", lastHeartRate: now.addingTimeInterval(-30), paused: false, now: now)
        #expect(quiet == .sensorQuiet(name: "WHOOP", seconds: 30))
        let none = LiveLink.assess(watchOwned: false, watchReachable: false, lastWatchPacket: nil,
                                   sensorName: nil, lastHeartRate: nil, paused: false, now: now)
        #expect(none == .noSource)
    }

    @Test func freshBeatsWithoutANamedStrapStillReadAsLive() {
        let link = LiveLink.assess(watchOwned: false, watchReachable: false, lastWatchPacket: nil,
                                   sensorName: nil, lastHeartRate: now.addingTimeInterval(-3), paused: false, now: now)
        #expect(link == .sensorLive(name: "Heart rate"))
        let stale = LiveLink.assess(watchOwned: false, watchReachable: false, lastWatchPacket: nil,
                                    sensorName: nil, lastHeartRate: now.addingTimeInterval(-60), paused: false, now: now)
        #expect(stale == .noSource)
    }

    @Test func swingPaceCountsTheLastMinuteOnly() {
        let moments = [-90, -59, -30, -1, 5].map { now.addingTimeInterval(TimeInterval($0)) }
        #expect(SwingPace.perMinute(moments, now: now) == 3)
    }
}
