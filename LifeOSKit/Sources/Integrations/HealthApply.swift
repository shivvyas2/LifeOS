import Foundation
import Persistence

/// Writes a day of Apple Health readings into the day's row.
///
/// The one place the `HealthMetric` vocabulary meets `DailyMetrics` columns.
/// Separated from `HealthKitReader` so the mapping can be tested against a real
/// store without a device, an authorisation prompt, or any Health data existing
/// on the machine running the tests. `MetricArbiter` can be perfectly correct
/// and still be wired into the wrong column, and only this layer catches that.
public enum HealthApply {

    /// Merges one day, honouring the ranks.
    ///
    /// Uses `MetricsStore.upsert`, which is a merge rather than a replace, so
    /// the columns Health has nothing to say about are left exactly as Whoop
    /// or the user left them.
    @MainActor
    public static func write(
        _ day: HealthDay,
        into store: MetricsStore,
        ranking: SourceRanking = SourceRanking()
    ) throws {
        try store.upsert(date: day.date) { row in
            for (metric, incoming) in day.values {
                let resolved = resolve(
                    metric, incoming: incoming, existing: existing(metric, in: row),
                    ranking: ranking, row: row
                )
                write(resolved, for: metric, into: row)
            }
        }
    }

    /// The named columns, read as a Double so one merge path serves them all.
    @MainActor
    private static func existing(_ metric: HealthMetric, in row: DailyMetrics) -> Double? {
        switch metric {
        case .steps:             row.steps.map(Double.init)
        case .exerciseMinutes:   row.exerciseMinutes.map(Double.init)
        case .sleepMinutes:      row.sleepMinutes.map(Double.init)
        case .activeEnergyKcal:  row.activeEnergyKcal
        case .weightKg:          row.weightKg
        case .waterML:           row.waterML
        case .restingHR:         row.restingHR
        case .hrvMs:             row.hrvMs
        case .spo2Percentage:    row.spo2Percentage
        case .respiratoryRate:   row.respiratoryRate
        default:                 row.extra(metric.rawValue)
        }
    }

    /// Decides, and records the attribution as a side effect so the next sync
    /// can arbitrate against it.
    @MainActor
    private static func resolve(
        _ metric: HealthMetric,
        incoming: Double?,
        existing: Double?,
        ranking: SourceRanking,
        row: DailyMetrics
    ) -> Double? {
        let held = row.source(metric.rawValue).flatMap(MetricSource.init(rawValue:))
        let outcome = MetricArbiter.resolve(
            metric: metric,
            existing: existing, existingSource: held,
            incoming: incoming, incomingSource: .appleHealth,
            ranking: ranking
        )
        row.setSource(metric.rawValue, outcome.source?.rawValue)
        return outcome.value
    }

    /// The one place the `HealthMetric` vocabulary meets `DailyMetrics` columns.
    @MainActor
    private static func write(_ value: Double?, for metric: HealthMetric, into row: DailyMetrics) {
        switch metric {
        case .steps:             row.steps = whole(value)
        case .exerciseMinutes:   row.exerciseMinutes = whole(value)
        case .sleepMinutes:      row.sleepMinutes = whole(value)
        case .activeEnergyKcal:  row.activeEnergyKcal = value
        case .weightKg:          row.weightKg = value
        case .waterML:           row.waterML = value
        case .restingHR:         row.restingHR = value
        case .hrvMs:             row.hrvMs = value
        case .spo2Percentage:    row.spo2Percentage = value
        case .respiratoryRate:   row.respiratoryRate = value
        default:
            // The long tail. Same merge rule, stored in the bag rather than in
            // a column of its own. See `DailyMetrics.extrasData`.
            row.setExtra(metric.rawValue, value)
        }
    }

    private static func whole(_ value: Double?) -> Int? {
        value.map { Int($0.rounded()) }
    }
}
