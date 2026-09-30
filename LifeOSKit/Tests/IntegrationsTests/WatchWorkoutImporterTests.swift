import Foundation
import SwiftData
import Testing
import AppSurfaces
import Persistence
@testable import Integrations

@MainActor
struct WatchWorkoutImporterTests {
    @Test func offlineRedeliveryUpdatesOneRowAndNeverCrossesAccounts() throws {
        let container = try ModelContainer(for: WorkoutRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date.now
        let summary = WatchWorkoutSummary(id: UUID(), ownerID: "alice", activity: "Strength", startedAt: now.addingTimeInterval(-1200),
            endedAt: now, elapsed: 900, energyKcal: 120, distanceMeters: nil, sets: [12, 10, 8], healthWorkoutID: UUID())
        let refused = try WatchWorkoutImporter.save(summary, ownerID: "bob", context: context)
        #expect(!refused)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 0)
        let saved = try WatchWorkoutImporter.save(summary, ownerID: "alice", context: context)
        #expect(saved)
        let first = try #require(context.fetch(FetchDescriptor<WorkoutRecord>()).first)
        first.videoID = "abc12345678"; first.split = "push"
        let repeated = try WatchWorkoutImporter.save(summary, ownerID: "alice", context: context)
        #expect(repeated)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 1)
        #expect(first.durationMinutes == 15)
        #expect(first.sets == [12, 10, 8])
        #expect(first.videoID == "abc12345678" && first.split == "push")
    }
    @Test func finalResultReconcilesAPhoneRecordSavedBeforeTheFirstPacket() throws {
        let container = try ModelContainer(for: WorkoutRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date.now
        let start = now.addingTimeInterval(-1200)
        let early = WorkoutRecord(externalID: "almanac:temporary-phone-id", start: start, durationMinutes: 20, activityName: "Run")
        context.insert(early)
        let summary = WatchWorkoutSummary(id: UUID(), ownerID: "alice", activity: "Run", startedAt: start, endedAt: now,
            elapsed: 900, energyKcal: 120, distanceMeters: 2000, sets: [], healthWorkoutID: UUID())
        let accepted = try WatchWorkoutImporter.save(summary, ownerID: "alice", context: context)
        #expect(accepted)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 1)
        #expect(early.externalID == summary.recordID && early.durationMinutes == 15)
    }

}
