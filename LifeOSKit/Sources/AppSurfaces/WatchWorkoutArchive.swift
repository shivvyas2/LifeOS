import Foundation

/// Account identity is independent of the short-lived widget data lease.
/// Contains no credentials and never authorizes access to a server.
public struct WatchAccountBinding: Codable, Equatable, Sendable {
    public var ownerID: String?
    public var updatedAt: Date
    public init(ownerID: String?, updatedAt: Date = .now) {
        self.ownerID = ownerID; self.updatedAt = updatedAt
    }
    public func supersedes(_ previous: Self?) -> Bool {
        previous.map { updatedAt > $0.updatedAt } ?? true
    }
}

/// Durable final result. Live commands are never queued for later execution.
public struct WatchWorkoutSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var ownerID: String
    public var activity: String
    public var startedAt: Date
    public var endedAt: Date
    public var elapsed: TimeInterval
    public var energyKcal: Double?
    public var distanceMeters: Double?
    public var sets: [Int]
    public var healthWorkoutID: UUID?
    public init(id: UUID, ownerID: String, activity: String, startedAt: Date, endedAt: Date,
                elapsed: TimeInterval, energyKcal: Double?, distanceMeters: Double?, sets: [Int], healthWorkoutID: UUID?) {
        self.id = id; self.ownerID = ownerID; self.activity = activity
        self.startedAt = startedAt; self.endedAt = endedAt; self.elapsed = elapsed
        self.energyKcal = energyKcal; self.distanceMeters = distanceMeters
        self.sets = sets; self.healthWorkoutID = healthWorkoutID
    }
    public var recordID: String { "almanac-watch:\(id.uuidString)" }
    public func isValid(for owner: String, now: Date = .now) -> Bool {
        ownerID == owner && !owner.isEmpty && ActivityCatalog.type(named: activity) != nil
        && startedAt <= endedAt && endedAt <= now.addingTimeInterval(60)
        && elapsed.isFinite && elapsed >= 0 && elapsed <= endedAt.timeIntervalSince(startedAt) + 2
        && elapsed <= 7 * 24 * 3600
        && (energyKcal.map { $0.isFinite && (0...100_000).contains($0) } ?? true)
        && (distanceMeters.map { $0.isFinite && (0...2_000_000).contains($0) } ?? true)
        && sets.count <= 1000 && sets.allSatisfy { (0...10000).contains($0) }
    }
}

public enum WatchWorkoutLayout: String, Sendable {
    case court, distance, strength, mindful, general
    public static func forActivity(_ activity: ActivityType) -> Self {
        if activity.countsReps { return .strength }
        if activity.tracksDistance { return .distance }
        if ["Badminton", "Tennis", "Table Tennis", "Pickleball", "Squash", "Racquetball"].contains(activity.name) { return .court }
        if activity.group == .mindAndBody && !activity.showsZones { return .mindful }
        return .general
    }
}
