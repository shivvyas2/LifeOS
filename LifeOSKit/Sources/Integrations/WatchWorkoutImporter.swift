import Foundation
import SwiftData
import AppSurfaces
import Persistence

/// Owner validation precedes any fetch. A repeated delivery enriches the same
/// row and preserves the library video/split recorded by the phone.
@MainActor
public enum WatchWorkoutImporter {
    public static func save(_ summary: WatchWorkoutSummary, ownerID: String, context: ModelContext, now: Date = .now) throws -> Bool {
        guard summary.isValid(for: ownerID, now: now) else { return false }
        let id = summary.recordID
        var request = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == id })
        request.fetchLimit = 1
        var existing = try context.fetch(request).first
        if existing == nil {
            // A phone can finish before the very first identity packet lands.
            // Reconcile only our own record for this exact start/activity.
            let start = summary.startedAt
            let name = summary.activity
            let candidates = try context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate {
                $0.start == start && $0.activityName == name
            }))
            existing = candidates.first { $0.externalID.hasPrefix("almanac:") }
            existing?.externalID = id
        }
        let row = existing ?? WorkoutRecord(externalID: id, start: summary.startedAt,
            durationMinutes: Int(summary.elapsed / 60), activityName: summary.activity)
        row.durationMinutes = Int(summary.elapsed / 60)
        row.energyKcal = summary.energyKcal; row.distanceMeters = summary.distanceMeters
        row.sets = summary.sets
        if let analysis = summary.swingAnalysis { row.swingAnalysisData = try JSONEncoder().encode(analysis) }
        if let session = summary.badminton { row.badmintonData = try JSONEncoder().encode(session) }
        if existing == nil { context.insert(row) }
        try context.save()
        return true
    }
}
