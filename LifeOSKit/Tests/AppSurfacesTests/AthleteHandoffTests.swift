import Testing
import Foundation
@testable import AppSurfaces

/// The phone's `configure` command carries the athlete profile, and the
/// Watch decides what to do with it: adopt it when it is newer than its own,
/// and start swing analysis on a badminton workout that began without one.
@Suite struct AthleteHandoffTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func profile(enabled: Bool = true, hand: ActivityAthleteProfile.Side = .right,
                         wrist: ActivityAthleteProfile.Side = .right, at: Date) -> ActivityAthleteProfile {
        ActivityAthleteProfile(playingHand: hand, watchWrist: wrist, motionEnabled: enabled, updatedAt: at)
    }

    @Test func theConfigureCommandCarriesTheProfile() throws {
        let athlete = profile(at: now)
        let envelope = PhoneCommandEnvelope(command: .configure, sentAt: now, maxHeartRate: 190, athlete: athlete)
        let back = try #require(WatchWire.command(from: try WatchWire.encode(envelope)))
        #expect(back == envelope)
        #expect(back.athlete == athlete)
    }

    @Test func aCommandWithoutTheProfileStillDecodes() throws {
        // What a phone running the previous build sends: the same version,
        // no `athlete` key at all.
        let json = #"{"kind":"command","v":2,"command":"configure","sentAt":1800000000,"maxHeartRate":180}"#
        let back = try #require(WatchWire.command(from: Data(json.utf8)))
        #expect(back.command == .configure && back.athlete == nil)
    }

    @Test func nothingArrivesNothingChanges() {
        // Only a profile that actually arrived can turn swings on; the
        // Watch's own profile had its say when the workout started.
        let decision = AthleteHandoff.decide(incoming: nil, current: profile(at: now), activityName: "Badminton", analyzing: false)
        #expect(decision == AthleteHandoff.Decision(adopt: nil, startsSwingAnalysis: false))
        let none = AthleteHandoff.decide(incoming: nil, current: nil, activityName: "Badminton", analyzing: false)
        #expect(none == AthleteHandoff.Decision(adopt: nil, startsSwingAnalysis: false))
    }

    @Test func aProfileFillsAnEmptyWatchAndStartsSwingsOnBadminton() {
        let incoming = profile(at: now)
        let decision = AthleteHandoff.decide(incoming: incoming, current: nil, activityName: "Badminton", analyzing: false)
        #expect(decision.adopt == incoming)
        #expect(decision.startsSwingAnalysis)
    }

    @Test func aNewerProfileReplacesTheWatchsOwn() {
        let old = profile(enabled: false, at: now.addingTimeInterval(-3600))
        let newer = profile(at: now)
        let decision = AthleteHandoff.decide(incoming: newer, current: old, activityName: "Badminton", analyzing: false)
        #expect(decision.adopt == newer && decision.startsSwingAnalysis)
    }

    @Test func anOlderOrEqualProfileIsIgnored() {
        let current = profile(at: now)
        let older = profile(enabled: false, at: now.addingTimeInterval(-60))
        #expect(AthleteHandoff.decide(incoming: older, current: current, activityName: "Badminton", analyzing: true).adopt == nil)
        let same = profile(enabled: false, at: now)
        #expect(AthleteHandoff.decide(incoming: same, current: current, activityName: "Badminton", analyzing: true).adopt == nil)
    }

    @Test func anInvalidProfileIsIgnored() {
        var broken = profile(at: now); broken.heightCM = 5
        let decision = AthleteHandoff.decide(incoming: broken, current: nil, activityName: "Badminton", analyzing: false)
        #expect(decision == AthleteHandoff.Decision(adopt: nil, startsSwingAnalysis: false))
    }

    @Test func swingsStartOnlyOnBadmintonOnlyOnceAndOnlyWhenTheProfileAllows() {
        let allows = profile(at: now)
        #expect(!AthleteHandoff.decide(incoming: allows, current: nil, activityName: "Tennis", analyzing: false).startsSwingAnalysis)
        #expect(!AthleteHandoff.decide(incoming: allows, current: nil, activityName: "Badminton", analyzing: true).startsSwingAnalysis)
        let wrongWrist = profile(hand: .right, wrist: .left, at: now)
        let decision = AthleteHandoff.decide(incoming: wrongWrist, current: nil, activityName: "Badminton", analyzing: false)
        #expect(decision.adopt == wrongWrist && !decision.startsSwingAnalysis)
        let off = profile(enabled: false, at: now)
        #expect(!AthleteHandoff.decide(incoming: off, current: nil, activityName: "Badminton", analyzing: false).startsSwingAnalysis)
    }
}
