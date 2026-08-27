import Foundation

/// Who put a number in the day's row.
///
/// Recorded per metric per day, because with two straps the value alone is no
/// longer enough to decide who wins. `fillGapsOnly` could not tell a Whoop
/// value from a typed one, which is exactly the distinction a second wearable
/// forces.
public enum MetricSource: String, Sendable, CaseIterable, Equatable {
    case manual
    case whoop
    case fitbit
    case appleHealth
}

/// Turns a source into a rank for a given metric.
///
/// A rank rather than a boolean, so that "the strap the user chose" can outrank
/// "the other strap" without either of them being hard-coded.
public struct SourceRanking: Sendable, Equatable {

    /// Whichever strap the user named as primary. Defaults to Whoop, which is
    /// the only one that exists before Fitbit ships, so an unset preference
    /// reproduces today's behaviour exactly.
    public let primaryWearable: MetricSource

    public init(primaryWearable: MetricSource = .whoop) {
        // A non-wearable primary is meaningless and would silently demote both
        // straps below the phone.
        self.primaryWearable = (primaryWearable == .fitbit) ? .fitbit : .whoop
    }

    /// 4 typed, 3 the authority, 2 a secondary reading, 1 a fallback, 0 unknown.
    public func rank(_ source: MetricSource?, for metric: HealthMetric) -> Int {
        guard let source else { return 0 }
        switch source {
        case .manual:
            return 4
        case .appleHealth:
            return metric.healthIsAuthoritative ? 3 : 1
        case .whoop, .fitbit:
            guard metric.claimedByWearable else { return 2 }
            return source == primaryWearable ? 3 : 2
        }
    }
}
