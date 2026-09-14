import Foundation
import Testing
@testable import AppSurfaces

struct LiveSessionReadoutTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func readoutRoundTripsAndKeepsAbsence() throws {
        var readout = LiveSessionReadout(elapsed: 90, runningSince: start, push: .onTrack)
        readout.heartRate = 142; readout.zone = 4; readout.effort = 9.3
        readout.calories = 210; readout.batteryPercent = 62; readout.capacitySource = "whoop"
        readout.ceilingMaxZone = 4; readout.ceilingTarget = 10...14
        let data = try JSONEncoder().encode(readout)
        let back = try JSONDecoder().decode(LiveSessionReadout.self, from: data)
        #expect(back == readout)
        #expect(back.distanceMeters == nil)
        #expect(back.timerAnchor == start.addingTimeInterval(-90))
        #expect(!back.isPaused)
    }

    @Test func pausedReadoutHasNoAnchor() {
        let readout = LiveSessionReadout(elapsed: 30, runningSince: nil, push: .easy)
        #expect(readout.timerAnchor == nil)
        #expect(readout.isPaused)
    }

    @Test func pushHeadlinesAreWords() {
        #expect(PushState.easy.headline == "Easy going")
        #expect(PushState.onTrack.headline == "On track")
        #expect(PushState.nearLimit.headline == "Near your limit")
        #expect(PushState.overLimit.headline == "Over your target")
    }
}
