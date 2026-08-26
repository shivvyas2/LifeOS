import Foundation
import Persistence

/// Body, from the metrics the app already collects.
///
/// Days on target carry twice the weight of the two averages, because a month
/// is made of days met or missed; the averages only say by how much.
public struct BodyScorer: SectorScorer {
    public let sector = LifeSector.body

    private let readings: [DayReading]
    private let targets: GoalTargets

    public init(readings: [DayReading], targets: GoalTargets) {
        self.readings = readings
        self.targets = targets
    }

    public func evidence() -> Evidence {
        let judged = readings.map { evaluate($0, against: targets) }
        let counted = judged.filter { $0 != .noData }
        guard !counted.isEmpty else { return Evidence() }

        let onTarget = counted.filter { $0 == .onTarget }.count
        var rows = [
            EvidenceRow(
                label: "days on target",
                value: "\(onTarget)/\(counted.count)",
                normalised: Double(onTarget) / Double(counted.count),
                weight: 2
            )
        ]

        if let row = average(
            label: "sleep vs goal",
            values: readings.compactMap { $0.sleepMinutes.map(Double.init) },
            goal: Double(targets.sleepMinutes),
            format: { "\(Int($0 / 60))h \(Int($0.truncatingRemainder(dividingBy: 60)))m" }
        ) {
            rows.append(row)
        }

        if let row = average(
            label: "exercise vs goal",
            values: readings.compactMap { $0.exerciseMinutes.map(Double.init) },
            goal: Double(targets.exerciseMinutes),
            format: { "\(Int($0))m" }
        ) {
            rows.append(row)
        }

        return Evidence(rows)
    }

    /// One row comparing a month's average against its goal.
    ///
    /// Returns nil rather than a zero row when nothing was logged, so an
    /// untracked metric stays absent from the reasoning instead of arguing
    /// against the person.
    private func average(
        label: String, values: [Double], goal: Double, format: (Double) -> String
    ) -> EvidenceRow? {
        guard !values.isEmpty, goal > 0 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return EvidenceRow(
            label: label, value: format(mean), normalised: mean / goal, // Relies on EvidenceRow clamping above 1.0 when mean exceeds goal
            weight: 1
        )
    }
}
