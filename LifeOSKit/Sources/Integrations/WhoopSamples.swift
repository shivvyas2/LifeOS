import Foundation

/// Neutral, already-parsed Whoop readings.
///
/// Deliberately separate from the wire DTOs. Whoop's JSON field names are the
/// one part of this integration that cannot be verified without a live token,
/// so decoding is isolated to `WhoopDTOs` and everything downstream (mapping,
/// attribution, tests) works on these plain values. If a field name is wrong,
/// exactly one small file changes.
public struct WhoopRecoverySample: Sendable, Equatable {
    /// The day this belongs to: the morning the cycle ended.
    public let date: Date
    public let recoveryPercentage: Double?
    public let restingHeartRate: Double?
    public let hrvMilliseconds: Double?
    public let spo2Percentage: Double?
    public let skinTempCelsius: Double?
    public let isCalibrating: Bool?

    public init(date: Date, recoveryPercentage: Double?, restingHeartRate: Double?,
                hrvMilliseconds: Double?, spo2Percentage: Double? = nil,
                skinTempCelsius: Double? = nil, isCalibrating: Bool? = nil) {
        self.date = date
        self.recoveryPercentage = recoveryPercentage
        self.restingHeartRate = restingHeartRate
        self.hrvMilliseconds = hrvMilliseconds
        self.spo2Percentage = spo2Percentage
        self.skinTempCelsius = skinTempCelsius
        self.isCalibrating = isCalibrating
    }
}

public struct WhoopSleepSample: Sendable, Equatable {
    public let externalID: String?
    public let start: Date
    public let end: Date
    public let isNap: Bool
    public let performancePercentage: Double?
    public let consistencyPercentage: Double?
    public let efficiencyPercentage: Double?
    public let respiratoryRate: Double?
    public let sleepNeedMinutes: Int?
    public let sleepDebtMinutes: Int?
    /// Time actually asleep, which is not time in bed.
    public let asleepMinutes: Int?
    public let lightMinutes: Int?
    public let remMinutes: Int?
    public let swsMinutes: Int?
    public let awakeMinutes: Int?
    public let noDataMinutes: Int?
    public let sleepCycleCount: Int?
    public let disturbanceCount: Int?

    public init(externalID: String? = nil, start: Date, end: Date, isNap: Bool = false,
                performancePercentage: Double?, consistencyPercentage: Double? = nil,
                efficiencyPercentage: Double? = nil,
                respiratoryRate: Double? = nil, sleepNeedMinutes: Int? = nil,
                sleepDebtMinutes: Int? = nil,
                asleepMinutes: Int?, lightMinutes: Int? = nil, remMinutes: Int? = nil,
                swsMinutes: Int? = nil, awakeMinutes: Int? = nil,
                noDataMinutes: Int? = nil, sleepCycleCount: Int? = nil,
                disturbanceCount: Int? = nil) {
        self.externalID = externalID
        self.start = start
        self.end = end
        self.isNap = isNap
        self.performancePercentage = performancePercentage
        self.consistencyPercentage = consistencyPercentage
        self.efficiencyPercentage = efficiencyPercentage
        self.respiratoryRate = respiratoryRate
        self.sleepNeedMinutes = sleepNeedMinutes
        self.sleepDebtMinutes = sleepDebtMinutes
        self.asleepMinutes = asleepMinutes
        self.lightMinutes = lightMinutes
        self.remMinutes = remMinutes
        self.swsMinutes = swsMinutes
        self.awakeMinutes = awakeMinutes
        self.noDataMinutes = noDataMinutes
        self.sleepCycleCount = sleepCycleCount
        self.disturbanceCount = disturbanceCount
    }
}

public struct WhoopCycleSample: Sendable, Equatable {
    public let date: Date
    public let dayStrain: Double?
    public let calories: Double?
    public let averageHR: Double?
    public let maxHR: Double?

    public init(date: Date, dayStrain: Double?, calories: Double? = nil,
                averageHR: Double? = nil, maxHR: Double? = nil) {
        self.date = date
        self.dayStrain = dayStrain
        self.calories = calories
        self.averageHR = averageHR
        self.maxHR = maxHR
    }
}

public struct WhoopWorkoutSample: Sendable, Equatable {
    public let externalID: String
    public let start: Date
    public let end: Date
    public let sportName: String
    public let sportID: Int?
    public let strain: Double?
    public let energyKcal: Double?
    public let averageHR: Double?
    public let maxHR: Double?
    public let percentRecorded: Double?
    public let distanceMeters: Double?
    public let altitudeGainMeters: Double?
    public let altitudeChangeMeters: Double?

    public init(externalID: String, start: Date, end: Date, sportName: String,
                sportID: Int? = nil, strain: Double? = nil, energyKcal: Double? = nil,
                averageHR: Double? = nil, maxHR: Double? = nil,
                percentRecorded: Double? = nil, distanceMeters: Double? = nil,
                altitudeGainMeters: Double? = nil, altitudeChangeMeters: Double? = nil) {
        self.externalID = externalID
        self.start = start
        self.end = end
        self.sportName = sportName
        self.sportID = sportID
        self.strain = strain
        self.energyKcal = energyKcal
        self.averageHR = averageHR
        self.maxHR = maxHR
        self.percentRecorded = percentRecorded
        self.distanceMeters = distanceMeters
        self.altitudeGainMeters = altitudeGainMeters
        self.altitudeChangeMeters = altitudeChangeMeters
    }

    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// The one-time body measurement Whoop reports: height, weight and max heart
/// rate. Unlike every other sample here, this carries no date of its own; it
/// is a current snapshot, not a per-day reading, so the caller supplies the
/// day it should be attributed to.
public struct WhoopBodySample: Sendable, Equatable {
    public let heightMeters: Double?
    public let weightKilograms: Double?
    public let maxHeartRate: Double?

    public init(heightMeters: Double?, weightKilograms: Double?, maxHeartRate: Double?) {
        self.heightMeters = heightMeters
        self.weightKilograms = weightKilograms
        self.maxHeartRate = maxHeartRate
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
