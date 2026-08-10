import Foundation

/// Neutral, already-parsed Whoop readings.
///
/// Deliberately separate from the wire DTOs. Whoop's JSON field names are the
/// one part of this integration that cannot be verified without a live token,
/// so decoding is isolated to `WhoopDTOs` and everything downstream — mapping,
/// attribution, tests — works on these plain values. If a field name is wrong,
/// exactly one small file changes.
public struct WhoopRecoverySample: Sendable, Equatable {
    /// The day this belongs to — the morning the cycle ended.
    public let date: Date
    public let recoveryPercentage: Double?
    public let restingHeartRate: Double?
    public let hrvMilliseconds: Double?

    public init(date: Date, recoveryPercentage: Double?, restingHeartRate: Double?, hrvMilliseconds: Double?) {
        self.date = date
        self.recoveryPercentage = recoveryPercentage
        self.restingHeartRate = restingHeartRate
        self.hrvMilliseconds = hrvMilliseconds
    }
}

public struct WhoopSleepSample: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let performancePercentage: Double?
    /// Time actually asleep, which is not time in bed.
    public let asleepMinutes: Int?

    public init(start: Date, end: Date, performancePercentage: Double?, asleepMinutes: Int?) {
        self.start = start
        self.end = end
        self.performancePercentage = performancePercentage
        self.asleepMinutes = asleepMinutes
    }
}

public struct WhoopCycleSample: Sendable, Equatable {
    public let date: Date
    public let dayStrain: Double?

    public init(date: Date, dayStrain: Double?) {
        self.date = date
        self.dayStrain = dayStrain
    }
}

public enum WhoopAttribution {
    /// A night's sleep belongs to the morning you woke up, not the evening you
    /// went to bed. Without this, anything after midnight lands on the wrong
    /// day and every sleep figure is off by one for late nights.
    public static func day(forSleepEndingAt end: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: end)
    }
}
