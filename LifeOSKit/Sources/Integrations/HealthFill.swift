import Foundation

/// A field Life OS can read out of Apple Health.
///
/// Deliberately its own enum rather than a set of HealthKit types: this file
/// carries the merge rules and must stay importable, testable and buildable
/// without the HealthKit framework. `HealthKitReader` owns the translation to
/// `HKQuantityType`.
public enum HealthMetric: String, CaseIterable, Sendable {
    case steps
    case activeEnergyKcal
    case exerciseMinutes
    case weightKg
    case waterML
    case restingHR
    case hrvMs
    case spo2Percentage
    case respiratoryRate
    case sleepMinutes

    /// Who owns this number when two sources disagree.
    public enum Precedence: Sendable, Equatable {
        /// Something else is the authority. Health writes only into a gap.
        ///
        /// Two different reasons land here. Whoop measures resting HR, HRV,
        /// SpO2, respiratory rate and sleep from a strap worn all night, and it
        /// stays the source of truth for them. Water and weight can be typed
        /// into the app by hand, and a background sync does not get to replace
        /// something a person entered on purpose.
        case fillGapsOnly
        /// Health is the only source there is, so its latest reading is simply
        /// the truth. Steps, active energy and exercise minutes are counted
        /// passively by the phone and the watch, nobody types them, and the
        /// number legitimately grows through the day. This precedence is what
        /// lets the afternoon sync correct the morning's count.
        case healthIsTheSource
    }

    public var precedence: Precedence {
        switch self {
        case .steps, .activeEnergyKcal, .exerciseMinutes:
            .healthIsTheSource
        case .weightKg, .waterML, .restingHR, .hrvMs,
             .spo2Percentage, .respiratoryRate, .sleepMinutes:
            .fillGapsOnly
        }
    }
}

/// The merge rule, as a pure function.
///
/// Kept apart from both HealthKit and SwiftData so every branch can be
/// exercised without a device, an authorisation prompt or a store. The sync
/// that uses it is a loop around this one call.
public enum HealthFill {

    /// What the day's row should hold after a Health reading arrives, given
    /// what it holds now.
    ///
    /// Returns `existing` unchanged when there is nothing to write, so a caller
    /// can assign the result unconditionally.
    public static func value(
        for metric: HealthMetric,
        existing: Double?,
        health: Double?
    ) -> Double? {
        // Health having no reading is not evidence of zero. Blanking a real
        // value because a query came back empty is the one failure here that
        // destroys data rather than merely showing the wrong number.
        guard let health else { return existing }

        switch metric.precedence {
        case .healthIsTheSource:
            return health
        case .fillGapsOnly:
            return existing ?? health
        }
    }
}
