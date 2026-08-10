import Foundation
import SwiftData

/// One row per calendar day — the join key for the entire app.
/// HealthKit and Whoop are both writers; the UI and the coach are readers.
///
/// Every metric is optional. A missing value and a zero must never be the
/// same thing: in a health app a false zero is worse than a blank.
@Model
public final class DailyMetrics {
    #Unique<DailyMetrics>([\.date])

    /// Always `Calendar.startOfDay`. Never a timestamp.
    public var date: Date

    public var weightKg: Double?
    public var steps: Int?
    public var activeEnergyKcal: Double?
    public var exerciseMinutes: Int?
    public var sleepMinutes: Int?
    public var waterML: Double?
    public var restingHR: Double?
    public var hrvMs: Double?

    public var whoopRecoveryPct: Double?
    public var whoopDayStrain: Double?
    public var whoopSleepPerformancePct: Double?

    public var updatedAt: Date
    public var syncedAt: Date?

    public init(date: Date) {
        self.date = date
        self.updatedAt = .now
    }

    public var reading: DayReading {
        DayReading(
            steps: steps,
            sleepMinutes: sleepMinutes,
            exerciseMinutes: exerciseMinutes,
            waterML: waterML
        )
    }
}
