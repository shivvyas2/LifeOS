import Foundation
import Persistence

/// How far a plan entry got this month, on the shared 0...1 scale.
///
/// Blocked returns nil rather than zero: waiting on someone else is not a
/// failure of the person being scored, so it is excluded rather than punished.
func progressFraction(_ status: PlanStatus) -> Double? {
    switch status {
    case .done:       1.0
    case .inProgress: 0.5
    case .scheduled:  0.25
    case .todo:       0.0
    case .blocked:    nil
    }
}

/// Mission, from what actually moved on the plan.
public struct MissionScorer: SectorScorer {
    public let sector = LifeSector.mission

    private let statuses: [PlanStatus]
    private let habitTickRate: Double?

    public init(statuses: [PlanStatus], habitTickRate: Double?) {
        self.statuses = statuses
        self.habitTickRate = habitTickRate
    }

    public func evidence() -> Evidence {
        let judged = statuses.compactMap(progressFraction)
        guard !judged.isEmpty else { return Evidence() }

        let done = statuses.filter { $0 == .done }.count
        var rows = [
            EvidenceRow(
                label: "goals moved",
                value: "\(done)/\(judged.count)",
                normalised: judged.reduce(0, +) / Double(judged.count),
                weight: 2
            )
        ]

        if let habitTickRate {
            rows.append(EvidenceRow(
                label: "habits kept",
                value: "\(Int((habitTickRate * 100).rounded()))%",
                normalised: habitTickRate,  // No caller currently produces a value outside 0...1; EvidenceRow's clamp is the backstop if one ever does.
                weight: 1
            ))
        }

        return Evidence(rows)
    }
}
