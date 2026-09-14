import Foundation
import Persistence

/// Today's capacity from the metrics store, shared by the recorder and the
/// workout planner so both read the same nine days the same way.
public enum CapacityInputs {
    @MainActor
    public static func todayCapacity(store: MetricsStore, now: Date = .now, calendar: Calendar = .current) -> Capacity? {
        let rows = (try? store.metrics(from: now.addingTimeInterval(-9 * 86400), to: now)) ?? []
        let days = rows.map {
            RecoveryDay(date: $0.date, whoopRecoveryPct: $0.whoopRecoveryPct, whoopIsCalibrating: $0.whoopRecoveryIsCalibrating,
                        sleepPerformancePct: $0.whoopSleepPerformancePct, hrvMs: $0.hrvMs, sleepMinutes: $0.sleepMinutes)
        }
        return CapacityMath.capacity(days: days, now: now, calendar: calendar)
    }
}
