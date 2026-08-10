import Foundation
import SwiftData
import Persistence

/// Writes Whoop readings into the daily spine.
///
/// Every write goes through `MetricsStore.upsertBatch`, so a re-sync merges
/// into the existing row rather than replacing it — HealthKit owns steps and
/// weight on the same row and must not be clobbered.
@MainActor
public struct WhoopIngestion {
    private let store: MetricsStore
    private let calendar: Calendar

    public init(store: MetricsStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func ingest(
        recoveries: [WhoopRecoverySample] = [],
        sleeps: [WhoopSleepSample] = [],
        cycles: [WhoopCycleSample] = []
    ) throws {
        // Index by day first so one day touched by all three sources is written
        // once, not three times.
        var byDay: [Date: (WhoopRecoverySample?, WhoopSleepSample?, WhoopCycleSample?)] = [:]

        for sample in recoveries {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day, default: (nil, nil, nil)].0 = sample
        }
        for sample in sleeps {
            let day = WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar)
            byDay[day, default: (nil, nil, nil)].1 = sample
        }
        for sample in cycles {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day, default: (nil, nil, nil)].2 = sample
        }

        guard !byDay.isEmpty else { return }

        try store.upsertBatch(dates: Array(byDay.keys)) { date, row in
            let day = calendar.startOfDay(for: date)
            guard let (recovery, sleep, cycle) = byDay[day] else { return }

            // Nil never overwrites a stored value: a sample that omits a field
            // means "no reading", not "clear what you had".
            if let value = recovery?.recoveryPercentage { row.whoopRecoveryPct = value }
            if let value = recovery?.restingHeartRate { row.restingHR = value }
            if let value = recovery?.hrvMilliseconds { row.hrvMs = value }

            if let value = sleep?.performancePercentage { row.whoopSleepPerformancePct = value }
            if let value = sleep?.asleepMinutes { row.sleepMinutes = value }

            if let value = cycle?.dayStrain { row.whoopDayStrain = value }

            row.syncedAt = .now
        }
    }
}
