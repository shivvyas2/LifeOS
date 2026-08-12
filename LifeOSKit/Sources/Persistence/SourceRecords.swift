import Foundation
import SwiftData

/// Source records roll *up* into `DailyMetrics`, which is derived state and
/// always safe to recompute from these.
@Model
public final class WorkoutRecord {
    public var externalID: String
    public var start: Date
    public var durationMinutes: Int
    public var activityName: String
    public var energyKcal: Double?

    public init(externalID: String, start: Date, durationMinutes: Int, activityName: String, energyKcal: Double? = nil) {
        self.externalID = externalID
        self.start = start
        self.durationMinutes = durationMinutes
        self.activityName = activityName
        self.energyKcal = energyKcal
    }
}

@Model
public final class SleepRecord {
    public var externalID: String
    public var start: Date
    public var end: Date
    /// The day this sleep is attributed to: the morning you woke up.
    public var attributedDate: Date

    public init(externalID: String, start: Date, end: Date, attributedDate: Date) {
        self.externalID = externalID
        self.start = start
        self.end = end
        self.attributedDate = attributedDate
    }

    public var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }
}
