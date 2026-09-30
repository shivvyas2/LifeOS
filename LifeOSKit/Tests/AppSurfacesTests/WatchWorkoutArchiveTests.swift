import Foundation
import Testing
@testable import AppSurfaces

struct WatchWorkoutArchiveTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func summary() -> WatchWorkoutSummary {
        WatchWorkoutSummary(id: UUID(), ownerID: "alice", activity: "Badminton",
            startedAt: now.addingTimeInterval(-1800), endedAt: now, elapsed: 1200,
            energyKcal: 145, distanceMeters: nil, sets: [], healthWorkoutID: UUID())
    }
    @Test func offlineSummaryKeepsOwnerAndStableIdentity() throws {
        let value = summary()
        let recovered = try JSONDecoder().decode(WatchWorkoutSummary.self, from: JSONEncoder().encode(value))
        #expect(recovered == value)
        #expect(recovered.recordID == value.recordID)
        #expect(recovered.isValid(for: "alice", now: now.addingTimeInterval(86400)))
        #expect(!recovered.isValid(for: "bob", now: now))
        #expect(!recovered.isValid(for: "", now: now))
    }
    @Test func impossibleMetricsAndFutureFinishesAreRejected() {
        var value = summary()
        value.elapsed = 1801
        #expect(value.isValid(for: "alice", now: now))
        value.elapsed = 1900
        #expect(!value.isValid(for: "alice", now: now))
        value = summary(); value.energyKcal = .nan
        #expect(!value.isValid(for: "alice", now: now))
        value = summary(); value.distanceMeters = -1
        #expect(!value.isValid(for: "alice", now: now))
        value = summary(); value.energyKcal = nil; value.distanceMeters = nil; value.sets = [-1]
        #expect(!value.isValid(for: "alice", now: now))
        value = summary(); value.endedAt = now.addingTimeInterval(120)
        #expect(!value.isValid(for: "alice", now: now))
    }
    @Test func signOutSupersedesBindingButAnOldDeliveryCannotRestoreIt() {
        let bound = WatchAccountBinding(ownerID: "alice", updatedAt: now)
        let cleared = WatchAccountBinding(ownerID: nil, updatedAt: now.addingTimeInterval(1))
        #expect(cleared.supersedes(bound))
        #expect(!bound.supersedes(cleared))
        #expect(!bound.supersedes(bound))
    }
    @Test func activityHUDUsesSupportedMetrics() throws {
        let expectations: [(String, WatchWorkoutLayout)] = [("Badminton", .court), ("Run", .distance), ("Strength", .strength), ("Yoga", .mindful), ("Swimming", .distance), ("Soccer", .general)]
        for (name, layout) in expectations {
            let activity = try #require(ActivityCatalog.type(named: name))
            #expect(WatchWorkoutLayout.forActivity(activity) == layout)
        }
    }
    @Test func livePacketCarriesPrimaryClockAndAccount() throws {
        var packet = WatchPacket(sentAt: now)
        packet.sessionID = UUID(); packet.ownerID = "alice"
        packet.elapsed = 1200; packet.paused = true; packet.distanceMeters = 4820
        #expect(WatchWire.packet(from: try WatchWire.encode(packet)) == packet)
    }
}
