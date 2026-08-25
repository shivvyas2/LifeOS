import Foundation

/// One vital sitting outside its own recent range.
///
/// Wording rule for anything rendered from this: descriptive, never
/// diagnostic. "Well above your baseline" is a fact; "see a doctor" is a
/// claim this data cannot support.
public struct AnomalyFinding: Equatable, Sendable, Identifiable {
    public enum Direction: Sendable, Equatable { case above, below }

    public let metric: String
    public let todayValue: Double
    public let baseline: Double
    public let direction: Direction

    public var id: String { metric }

    public init(metric: String, todayValue: Double, baseline: Double, direction: Direction) {
        self.metric = metric
        self.todayValue = todayValue
        self.baseline = baseline
        self.direction = direction
    }
}

/// How far from baseline counts as abnormal, per metric. Percent for metrics
/// that scale with the person (heart rate), absolute for metrics with a
/// physiological unit (a degree of skin temperature means the same at any
/// baseline).
public enum AnomalyThreshold: Sendable, Equatable {
    case relativeAbove(Double)
    case relativeBelow(Double)
    case absoluteAbove(Double)
    case absoluteBelow(Double)
}

public enum AnomalyEvaluation {
    /// Below this many actual readings the baseline is noise, and a noisy
    /// baseline raises false alarms. No baseline → no verdict, same as the
    /// app-wide rule that absence of data is never a judgement.
    public static let minimumBaselineDays = 7

    public static func baseline(from history: [Double?]) -> Double? {
        let readings = history.compactMap { $0 }
        guard readings.count >= minimumBaselineDays else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    public static func evaluate(
        metric: String, today: Double?, history: [Double?],
        threshold: AnomalyThreshold
    ) -> AnomalyFinding? {
        guard let today, let baseline = baseline(from: history) else { return nil }

        let flagged: AnomalyFinding.Direction? = switch threshold {
        case .relativeAbove(let fraction):
            today >= baseline * (1 + fraction) ? .above : nil
        case .relativeBelow(let fraction):
            today <= baseline * (1 - fraction) ? .below : nil
        case .absoluteAbove(let delta):
            today >= baseline + delta ? .above : nil
        case .absoluteBelow(let delta):
            today <= baseline - delta ? .below : nil
        }

        guard let flagged else { return nil }
        return AnomalyFinding(metric: metric, todayValue: today,
                              baseline: baseline, direction: flagged)
    }
}
