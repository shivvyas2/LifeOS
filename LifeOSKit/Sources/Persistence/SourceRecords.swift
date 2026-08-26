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
    public var strain: Double?
    public var averageHR: Double?
    public var maxHR: Double?
    public var distanceMeters: Double?
    public var altitudeGainMeters: Double?
    public var altitudeChangeMeters: Double?
    /// Whoop reports how much of the workout it actually captured. A workout at
    /// 40 percent recorded is not a workout with a low strain, and collapsing
    /// the two would be the false zero this app refuses.
    public var percentRecorded: Double?
    public var sportID: Int?
    /// Minutes in each heart rate zone, 0 through 5. Six optional columns
    /// rather than one array because SwiftData stores scalars cleanly and an
    /// array attribute is a migration this does not need.
    public var zoneZeroMinutes: Int?
    public var zoneOneMinutes: Int?
    public var zoneTwoMinutes: Int?
    public var zoneThreeMinutes: Int?
    public var zoneFourMinutes: Int?
    public var zoneFiveMinutes: Int?

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

    public var performancePercentage: Double?
    public var consistencyPercentage: Double?
    public var efficiencyPercentage: Double?
    public var lightMinutes: Int?
    public var remMinutes: Int?
    public var swsMinutes: Int?
    public var awakeMinutes: Int?
    public var noDataMinutes: Int?
    public var sleepCycleCount: Int?
    public var respiratoryRate: Double?
    public var sleepNeedMinutes: Int?
    public var sleepDebtMinutes: Int?
    public var needFromStrainMinutes: Int?
    /// Negative or zero: a recent nap reduces need.
    public var needFromNapMinutes: Int?
    public var disturbanceCount: Int?
    /// Optional rather than a defaulted Bool, because a non-optional addition
    /// is what turns a lightweight migration into a store that will not open.
    public var isNap: Bool?

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
