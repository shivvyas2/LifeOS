import Foundation

/// The merge rule, as a pure function.
///
/// Kept apart from HealthKit, Fitbit and SwiftData so every branch can be
/// exercised without a device, an authorisation prompt, a network or a store.
/// Each sync that uses it is a loop around this one call.
public enum MetricArbiter {

    /// What the day's row should hold after a reading arrives, and who it
    /// should then be attributed to.
    ///
    /// Returns `existing` unchanged when there is nothing to write, so a caller
    /// can assign the result unconditionally.
    public static func resolve(
        metric: HealthMetric,
        existing: Double?,
        existingSource: MetricSource?,
        incoming: Double?,
        incomingSource: MetricSource,
        ranking: SourceRanking
    ) -> (value: Double?, source: MetricSource?) {
        // A source having no reading is not evidence of zero.
        guard let incoming else { return (existing, existingSource) }
        guard existing != nil else { return (incoming, incomingSource) }

        let held = existingSource ?? MetricSource.legacy(for: metric)

        // Greater than or equal, not greater than. Equal rank means the same
        // source syncing again, which must be allowed to correct itself.
        guard ranking.rank(incomingSource, for: metric) >= ranking.rank(held, for: metric) else {
            return (existing, held)
        }
        return (incoming, incomingSource)
    }
}

extension MetricSource {

    /// How to read a value written before provenance was recorded.
    ///
    /// Rank 0 for almost everything, so the first sync after upgrade
    /// re-attributes it. The numbers do not change: the same sources produce
    /// them, now named.
    ///
    /// Weight and water are the exception, and the exception matters. A figure
    /// the user typed before this shipped is unattributed too, and treating it
    /// as unknown would let the next Health sync silently replace it. That is
    /// the one path here that destroys data a person entered by hand, so an
    /// unattributed value for a typed metric is read as typed.
    public static func legacy(for metric: HealthMetric) -> MetricSource? {
        metric.acceptsManualEntry ? .manual : nil
    }
}
