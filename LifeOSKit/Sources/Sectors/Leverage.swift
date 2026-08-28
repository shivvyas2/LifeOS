import Foundation
import Persistence

/// What one lever is worth, in points on the 0...10 scale.
public struct LeverDelta: Sendable, Equatable, Identifiable {
    public let lever: Lever
    public let delta: Double

    public var id: Lever { lever }

    public init(lever: Lever, delta: Double) {
        self.lever = lever
        self.delta = delta
    }
}

/// Which remaining lever moves a sector's score most.
///
/// A sensitivity reading, not a recommendation engine: each lever is scored
/// by perfecting it alone against a coasting month and taking the difference.
/// Because every variant is built on the same coast, no lever borrows credit
/// from another quietly improving beside it.
public enum Leverage {
    public static func ranked(
        for sector: LifeSector,
        inputs: MonthInputs,
        progress: MonthProgress,
        answers: [String: String],
        calendar: Calendar = .current
    ) -> [LeverDelta] {
        func value(_ projected: MonthInputs) -> Double? {
            SectorEvidenceFactory.evidence(
                for: sector, inputs: projected, answers: answers, calendar: calendar
            ).proposedValue
        }

        guard let base = value(
            ProjectedInputs.coasting(inputs, progress: progress, calendar: calendar)
        ) else { return [] }

        return Lever.all(for: sector)
            .filter { $0.tracked(in: inputs) }
            .map { lever in
                let projected = ProjectedInputs.perfecting(
                    lever, in: inputs, progress: progress, calendar: calendar
                )
                // Never negative: perfecting a lever cannot make a month
                // worse, and a negative row would read as advice to stop.
                return LeverDelta(lever: lever, delta: max(0, (value(projected) ?? base) - base))
            }
            .sorted { $0.delta > $1.delta }
    }
}
