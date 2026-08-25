import Foundation

/// One line of reasoning behind a proposed score.
///
/// `value` is the figure as it should be shown, already formatted. The close
/// screen renders these rows directly, which is what stops the explanation
/// drifting away from the arithmetic that produced the number.
public struct EvidenceRow: Codable, Sendable, Equatable {
    public let label: String
    public let value: String
    /// Always within 0...1. Clamped on the way in rather than trusted.
    public let normalised: Double
    /// Never negative. A zero-weight row is shown but does not count.
    public let weight: Double

    public init(label: String, value: String, normalised: Double, weight: Double = 1) {
        self.label = label
        self.value = value
        self.normalised = min(max(normalised, 0), 1)
        self.weight = max(weight, 0)
    }
}

/// The rows behind one sector-month, and the number they add up to.
///
/// Every sector uses this one rule, so a sector with two rows behaves exactly
/// like a sector with six and there is a single arithmetic path to test.
public struct Evidence: Codable, Sendable, Equatable {
    public let rows: [EvidenceRow]

    public init(_ rows: [EvidenceRow] = []) {
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }

    /// The weighted mean of the rows, on a 0...10 scale.
    ///
    /// `nil` when there is nothing to go on. Deliberately not zero: a sector
    /// with no evidence has not been judged badly, it has not been judged.
    public var proposedScore: Int? {
        guard !rows.isEmpty else { return nil }
        let totalWeight = rows.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weighted = rows.reduce(0) { $0 + $1.normalised * $1.weight }
        return Int(((weighted / totalWeight) * 10).rounded())
    }
}
