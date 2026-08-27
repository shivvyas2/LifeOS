import Foundation

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
