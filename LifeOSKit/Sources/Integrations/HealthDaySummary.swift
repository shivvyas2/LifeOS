import Foundation
import Persistence

/// Everything a day actually holds, ready to list.
///
/// The point of this type is that the screen does not choose what to show. A
/// person with a cuff has blood pressure and a person without does not; a phone
/// records gait whether or not its owner asked. Enumerating the metrics that
/// have a value, rather than hard-coding rows and letting most of them render a
/// dash, is what makes the health screen reflect the person using it.
public enum HealthDaySummary {

    public struct Item: Identifiable, Equatable, Sendable {
        public let metric: HealthMetric
        public let value: Double
        public var id: String { metric.rawValue }
        public var title: String { metric.title }
        public var formatted: String { metric.formatted(value) }
    }

    public struct Group: Identifiable, Equatable, Sendable {
        public let group: HealthMetric.Group
        public let items: [Item]
        public var id: String { group.rawValue }
        public var title: String { group.title }
    }

    /// Named columns first, then the bag, then grouped in the enum's own order
    /// so the panels and the rows inside them are stable from day to day. A
    /// list that reorders itself as values appear is unreadable.
    @MainActor
    public static func groups(for row: DailyMetrics?) -> [Group] {
        guard let row else { return [] }

        var values: [HealthMetric: Double] = [:]
        for metric in HealthMetric.allCases {
            if let value = named(metric, in: row) ?? row.extra(metric.rawValue) {
                values[metric] = value
            }
        }

        return HealthMetric.Group.allCases.compactMap { group in
            let items = HealthMetric.allCases
                .filter { $0.group == group }
                .compactMap { metric in
                    values[metric].map { Item(metric: metric, value: $0) }
                }
            return items.isEmpty ? nil : Group(group: group, items: items)
        }
    }

    /// The ten that predate the bag and still have columns of their own,
    /// because the scorers and charts read them by name.
    @MainActor
    private static func named(_ metric: HealthMetric, in row: DailyMetrics) -> Double? {
        switch metric {
        case .steps:            row.steps.map(Double.init)
        case .exerciseMinutes:  row.exerciseMinutes.map(Double.init)
        case .sleepMinutes:     row.sleepMinutes.map(Double.init)
        case .activeEnergyKcal: row.activeEnergyKcal
        case .weightKg:         row.weightKg
        case .waterML:          row.waterML
        case .restingHR:        row.restingHR
        case .hrvMs:            row.hrvMs
        case .spo2Percentage:   row.spo2Percentage
        case .respiratoryRate:  row.respiratoryRate
        default:                nil
        }
    }
}
