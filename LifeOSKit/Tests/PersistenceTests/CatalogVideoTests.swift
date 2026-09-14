import Foundation
import SwiftData
import Testing
@testable import Persistence

struct CatalogVideoTests {
    @Test @MainActor func upsertIsIdempotentAndRemovesMissingRows() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let a = CatalogVideoRow(youtubeID: "aaaaaaaaaaa", title: "A", channel: "C", durationS: 1800, goal: ["strength"], split: "push", muscles: [], equipment: ["none"], intensity: 2, verifiedAt: .now)
        let b = CatalogVideoRow(youtubeID: "bbbbbbbbbbb", title: "B", channel: "C", durationS: 1200, goal: ["mobility"], split: "mobility", muscles: [], equipment: [], intensity: 1, verifiedAt: .now)
        try CatalogStore.upsert([a, b], context: context)
        try CatalogStore.upsert([a, b], context: context)
        #expect(try CatalogStore.all(context: context).count == 2)
        try CatalogStore.upsert([a], context: context)
        let rows = try CatalogStore.all(context: context)
        #expect(rows.count == 1 && rows.first?.youtubeID == "aaaaaaaaaaa")
        #expect(rows.first?.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/aaaaaaaaaaa/hqdefault.jpg")
    }

    @Test func goalsAndWorkoutColumnsDefaultToAbsent() {
        let goals = UserGoals()
        #expect(goals.trainingGoal == nil && goals.equipmentRaw.isEmpty && goals.sessionMinutes == nil)
        let row = WorkoutRecord(externalID: "x", start: .now, durationMinutes: 1, activityName: "Strength")
        #expect(row.split == nil && row.videoID == nil)
    }
}
