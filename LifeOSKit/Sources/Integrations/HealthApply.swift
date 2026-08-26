import Foundation
import Persistence

/// Writes a day of Apple Health readings into the day's row.
///
/// The one place the `HealthMetric` vocabulary meets `DailyMetrics` columns.
/// Separated from `HealthKitReader` so the mapping can be tested against a real
/// store without a device, an authorisation prompt, or any Health data existing
/// on the machine running the tests. `HealthFill` can be perfectly correct and
/// still be wired into the wrong column, and only this layer catches that.
public enum HealthApply {

    /// Merges one day, honouring the precedence rules.
    ///
    /// Uses `MetricsStore.upsert`, which is a merge rather than a replace, so
    /// the columns Health has nothing to say about are left exactly as Whoop
    /// or the user left them.
    @MainActor
    public static func write(_ day: HealthDay, into store: MetricsStore) throws {
        try store.upsert(date: day.date) { row in
            for metric in HealthMetric.allCases {
                let incoming = day.values[metric]
                switch metric {
                case .steps:
                    row.steps = whole(HealthFill.value(for: metric, existing: row.steps.map(Double.init), health: incoming))
                case .exerciseMinutes:
                    row.exerciseMinutes = whole(HealthFill.value(for: metric, existing: row.exerciseMinutes.map(Double.init), health: incoming))
                case .sleepMinutes:
                    row.sleepMinutes = whole(HealthFill.value(for: metric, existing: row.sleepMinutes.map(Double.init), health: incoming))
                case .activeEnergyKcal:
                    row.activeEnergyKcal = HealthFill.value(for: metric, existing: row.activeEnergyKcal, health: incoming)
                case .weightKg:
                    row.weightKg = HealthFill.value(for: metric, existing: row.weightKg, health: incoming)
                case .waterML:
                    row.waterML = HealthFill.value(for: metric, existing: row.waterML, health: incoming)
                case .restingHR:
                    row.restingHR = HealthFill.value(for: metric, existing: row.restingHR, health: incoming)
                case .hrvMs:
                    row.hrvMs = HealthFill.value(for: metric, existing: row.hrvMs, health: incoming)
                case .spo2Percentage:
                    row.spo2Percentage = HealthFill.value(for: metric, existing: row.spo2Percentage, health: incoming)
                case .respiratoryRate:
                    row.respiratoryRate = HealthFill.value(for: metric, existing: row.respiratoryRate, health: incoming)
                }
            }
        }
    }

    /// Counts are stored as integers. HealthKit hands back a `Double` even for
    /// a step count, and rounding at the boundary keeps "9770.6 steps" from
    /// ever reaching a screen.
    private static func whole(_ value: Double?) -> Int? {
        value.map { Int($0.rounded()) }
    }
}
