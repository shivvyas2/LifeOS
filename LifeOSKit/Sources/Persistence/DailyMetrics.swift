import Foundation
import SwiftData

/// One row per calendar day, the join key for the entire app.
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

    /// The scored daily surface Whoop reports. Height and max heart rate are
    /// deliberately absent: they are constants, and a column restating the same
    /// value on every row is noise.
    public var spo2Percentage: Double?
    public var skinTempCelsius: Double?
    public var respiratoryRate: Double?
    public var whoopCalories: Double?
    public var whoopAverageHR: Double?
    public var whoopMaxHR: Double?
    public var whoopSleepConsistencyPct: Double?
    public var whoopSleepEfficiencyPct: Double?
    public var whoopSleepDebtMinutes: Int?

    /// True while Whoop is still calibrating to the user. A recovery score
    /// produced during calibration is not a score that supports a comparison,
    /// and presenting it unqualified is the same class of error as a false
    /// zero. Optional, so an existing store migrates.
    public var whoopRecoveryIsCalibrating: Bool?

    /// Everything Apple Health can supply that does not have a column of its
    /// own, as a JSON dictionary keyed by `HealthMetric.rawValue`.
    ///
    /// The named columns above came first and are load-bearing: the sector
    /// scorers, the Whoop merge and the charts all read them by name. The rest
    /// of Health is a long and growing tail, most of which a given person has
    /// no data for at all, and a column each would mean a schema change per
    /// metric for fields nothing queries. A bag keeps adding a metric to one
    /// enum case and one mapping.
    ///
    /// The distinction a bag must not lose is the one this whole model is
    /// built on: absent and zero are different. A key that is missing means no
    /// reading, and nothing writes a zero to stand in for one.
    public var extrasData: Data?

    /// Who wrote each value, as a JSON dictionary keyed by `HealthMetric.rawValue`.
    ///
    /// Parallel to `extrasData` rather than folded into it, because that bag is
    /// `[String: Double]` and a source is a name. Optional, so a store written
    /// before this existed migrates without a schema change and simply reports
    /// no provenance, which the arbiter reads as "unattributed".
    ///
    /// A raw `String` rather than a typed source: `Persistence` sits below
    /// `Integrations` and must not import it. The vocabulary lives up there.
    public var sourcesData: Data?

    public var updatedAt: Date
    public var syncedAt: Date?

    public init(date: Date) {
        self.date = date
        self.updatedAt = .now
    }

    /// The bag, decoded. Empty rather than throwing when the bytes cannot be
    /// read: a day whose extras are unreadable still has its named columns,
    /// and losing the screen over the tail would be the worse failure.
    public var extras: [String: Double] {
        get {
            guard let extrasData, !extrasData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: Double].self, from: extrasData)
            else { return [:] }
            return decoded
        }
        set {
            extrasData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    public func extra(_ key: String) -> Double? { extras[key] }

    /// Writing nil removes the key rather than storing a zero, for the reason
    /// in the property comment above.
    public func setExtra(_ key: String, _ value: Double?) {
        var bag = extras
        if let value { bag[key] = value } else { bag.removeValue(forKey: key) }
        extras = bag
    }

    /// The provenance bag, decoded. Empty rather than throwing when the bytes
    /// cannot be read, for the same reason `extras` is: a day whose
    /// attribution is unreadable still has its numbers.
    public var sources: [String: String] {
        get {
            guard let sourcesData, !sourcesData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: String].self, from: sourcesData)
            else { return [:] }
            return decoded
        }
        set {
            sourcesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    public func source(_ key: String) -> String? { sources[key] }

    /// Writing nil removes the key, so an absent attribution stays absent
    /// rather than becoming a source with an empty name.
    public func setSource(_ key: String, _ value: String?) {
        var bag = sources
        if let value { bag[key] = value } else { bag.removeValue(forKey: key) }
        sources = bag
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
