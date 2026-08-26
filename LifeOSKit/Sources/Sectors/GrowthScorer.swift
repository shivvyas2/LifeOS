import Foundation
import Persistence

/// Growth, from the targets set in `UserGoals` and the goals raised against them.
public struct GrowthScorer: SectorScorer {
    public let sector = LifeSector.growth

    private let goalStatuses: [PlanStatus]
    private let targetsMet: Int
    private let targetsTotal: Int

    public init(goalStatuses: [PlanStatus], targetsMet: Int, targetsTotal: Int) {
        self.goalStatuses = goalStatuses
        self.targetsMet = targetsMet
        self.targetsTotal = targetsTotal
    }

    public func evidence() -> Evidence {
        var rows: [EvidenceRow] = []

        if targetsTotal > 0 {
            rows.append(EvidenceRow(
                label: "targets met",
                value: "\(targetsMet)/\(targetsTotal)",
                normalised: Double(targetsMet) / Double(targetsTotal),
                weight: 2
            ))
        }

        let judged = goalStatuses.compactMap(progressFraction)
        if !judged.isEmpty {
            let done = goalStatuses.filter { $0 == .done }.count
            rows.append(EvidenceRow(
                label: "goals completed",
                value: "\(done)/\(judged.count)",
                normalised: judged.reduce(0, +) / Double(judged.count),
                weight: 1
            ))
        }

        return Evidence(rows)
    }
}
