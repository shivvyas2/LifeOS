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

    private func readout(bpm: Int?, effort: Double? = 5, paused: Bool = false, push: PushState = .onTrack) -> LiveSessionReadout {
        var value = LiveSessionReadout(elapsed: 60, runningSince: paused ? nil : start, push: push)
        value.heartRate = bpm; value.effort = effort
        return value
    }

    @Test func throttlePublishesFirstAndOnMeaningfulChange() {
        let now = start.addingTimeInterval(100)
        #expect(LiveActivityThrottle.shouldPublish(previous: nil, next: readout(bpm: 120), lastPublishedAt: nil, now: now))
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 121), lastPublishedAt: now.addingTimeInterval(-2), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 123), lastPublishedAt: now.addingTimeInterval(-3), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: nil), lastPublishedAt: now.addingTimeInterval(-3), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120, push: .nearLimit), lastPublishedAt: now.addingTimeInterval(-1), now: now))
    }

    @Test func throttleSpacesHeartRateUpdates() {
        let now = start.addingTimeInterval(200)
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 123), lastPublishedAt: now.addingTimeInterval(-1), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 123), lastPublishedAt: now.addingTimeInterval(-3), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120, push: .nearLimit), lastPublishedAt: now.addingTimeInterval(-1), now: now))
    }

    @Test func throttleFloorsSmallChangesAtTenSeconds() {
        let now = start.addingTimeInterval(100)
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120, effort: 5.0), next: readout(bpm: 120, effort: 5.1), lastPublishedAt: now.addingTimeInterval(-4), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120, effort: 5.0), next: readout(bpm: 120, effort: 5.1), lastPublishedAt: now.addingTimeInterval(-10), now: now))
        #expect(!LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120), lastPublishedAt: now.addingTimeInterval(-60), now: now))
        #expect(LiveActivityThrottle.shouldPublish(previous: readout(bpm: 120), next: readout(bpm: 120, paused: true), lastPublishedAt: now, now: now))
    }

    @Test func textFormattersKeepAbsenceAndRounding() {
        var readout = LiveSessionReadout(elapsed: 0, runningSince: nil, push: .onTrack)
        #expect(readout.heartRateText == nil && readout.effortText == nil && readout.batteryText == nil)
        #expect(readout.caloriesText == nil && readout.distanceKilometresText == nil)
        #expect(readout.zoneText == nil && readout.capacitySourceName == "Battery unknown")
        readout.heartRate = 152; readout.zone = 4; readout.effort = 3.45; readout.calories = 0
        readout.distanceMeters = 1234; readout.batteryPercent = 0; readout.capacitySource = "whoop"
        #expect(readout.heartRateText == "152" && readout.zoneText == "Z4" && readout.effortText == "3.5")
        #expect(readout.caloriesText == "0" && readout.distanceKilometresText == "1.23" && readout.batteryText == "0%")
        #expect(readout.capacitySourceName == "WHOOP recovery")
    }
}
