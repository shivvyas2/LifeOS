import Foundation
import SwiftData
import Persistence

/// Rolls Whoop readings into the daily spine and the source records.
///
/// Replaces `WhoopIngestion` and keeps its two load-bearing properties: every
/// write goes through `MetricsStore.upsertBatch`, so a re-sync merges into the
/// existing row rather than replacing it, and a nil field never overwrites a
/// stored value. HealthKit owns steps and weight on the same row and must not
/// be clobbered.
@MainActor
public struct WhoopDerivation {
    private let store: MetricsStore
    private let archive: WhoopArchive
    private let calendar: Calendar

    public init(store: MetricsStore, archive: WhoopArchive, calendar: Calendar = .current) {
        self.store = store
        self.archive = archive
        self.calendar = calendar
    }

    public func derive(
        recoveries: [WhoopRecoverySample] = [],
        sleeps: [WhoopSleepSample] = [],
        cycles: [WhoopCycleSample] = []
    ) throws {
        try storeSleepRecords(sleeps)

        // Index by day first so one day touched by all three sources is written
        // once, not three times. Naps are excluded here and here only: they are
        // stored above as records, but a nap is not the night and must not
        // overwrite it.
        var byDay: [Date: (WhoopRecoverySample?, WhoopSleepSample?, WhoopCycleSample?)] = [:]

        for sample in recoveries {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day, default: (nil, nil, nil)].0 = sample
        }
        for sample in sleeps where !sample.isNap {
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
            if let value = recovery?.spo2Percentage { row.spo2Percentage = value }
            if let value = recovery?.skinTempCelsius { row.skinTempCelsius = value }

            if let value = sleep?.performancePercentage { row.whoopSleepPerformancePct = value }
            if let value = sleep?.asleepMinutes { row.sleepMinutes = value }
            if let value = sleep?.respiratoryRate { row.respiratoryRate = value }
            if let value = sleep?.consistencyPercentage { row.whoopSleepConsistencyPct = value }
            if let value = sleep?.efficiencyPercentage { row.whoopSleepEfficiencyPct = value }
            if let value = sleep?.sleepDebtMinutes { row.whoopSleepDebtMinutes = value }

            if let value = cycle?.dayStrain { row.whoopDayStrain = value }
            if let value = cycle?.calories { row.whoopCalories = value }
            if let value = cycle?.averageHR { row.whoopAverageHR = value }
            if let value = cycle?.maxHR { row.whoopMaxHR = value }

            row.syncedAt = .now
        }
    }

    /// Rebuilds every metric row from the archive, with no network call. This is
    /// the capability the archive exists for: a derivation bug found months from
    /// now is fixable without asking Whoop for the data again.
    @discardableResult
    public func rederive() throws -> Int {
        let recoveries = try decode(kind: "recovery", as: WhoopDTOs.RecoveryRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map {
                WhoopRecoverySample(
                    date: $0.created_at,
                    recoveryPercentage: $0.score?.recovery_score,
                    restingHeartRate: $0.score?.resting_heart_rate,
                    hrvMilliseconds: $0.score?.hrv_rmssd_milli,
                    spo2Percentage: $0.score?.spo2_percentage,
                    skinTempCelsius: $0.score?.skin_temp_celsius
                )
            }

        let cycles = try decode(kind: "cycle", as: WhoopDTOs.CycleRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map {
                WhoopCycleSample(
                    date: $0.start,
                    dayStrain: $0.score?.strain,
                    calories: $0.score?.kilojoule.map { $0 / 4.184 },
                    averageHR: $0.score?.average_heart_rate,
                    maxHR: $0.score?.max_heart_rate
                )
            }

        let sleeps = try decode(kind: "sleep", as: WhoopDTOs.SleepRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map { record -> WhoopSleepSample in
                let stages = record.score?.stage_summary
                let need = record.score?.sleep_needed
                return WhoopSleepSample(
                    externalID: record.id,
                    start: record.start,
                    end: record.end,
                    isNap: record.nap == true,
                    performancePercentage: record.score?.sleep_performance_percentage,
                    efficiencyPercentage: record.score?.sleep_efficiency_percentage,
                    respiratoryRate: record.score?.respiratory_rate,
                    sleepNeedMinutes: WhoopSleepMath.minutes(fromMilliseconds: need?.baseline_milli),
                    asleepMinutes: WhoopSleepMath.asleepMinutes(from: stages),
                    lightMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_light_sleep_time_milli),
                    remMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_rem_sleep_time_milli),
                    swsMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_slow_wave_sleep_time_milli),
                    awakeMinutes: WhoopSleepMath.minutes(fromMilliseconds: stages?.total_awake_time_milli),
                    disturbanceCount: stages?.disturbance_count
                )
            }

        try derive(recoveries: recoveries, sleeps: sleeps, cycles: cycles)

        var days = Set<Date>()
        for sample in recoveries { days.insert(calendar.startOfDay(for: sample.date)) }
        for sample in cycles { days.insert(calendar.startOfDay(for: sample.date)) }
        for sample in sleeps where !sample.isNap {
            days.insert(WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar))
        }
        return days.count
    }

    private func decode<Record: Decodable>(kind: String, as: Record.Type) throws -> [Record] {
        try archive.payloads(kind: kind).compactMap {
            // A single unreadable payload must not fail the whole re-derivation.
            try? WhoopClient.decoder.decode(Record.self, from: $0)
        }
    }

    private func storeSleepRecords(_ sleeps: [WhoopSleepSample]) throws {
        for sample in sleeps {
            guard let externalID = sample.externalID else { continue }
            try store.upsertSleepRecord(
                externalID: externalID,
                start: sample.start,
                end: sample.end,
                attributedDate: WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar)
            ) { record in
                record.performancePercentage = sample.performancePercentage
                record.lightMinutes = sample.lightMinutes
                record.remMinutes = sample.remMinutes
                record.swsMinutes = sample.swsMinutes
                record.awakeMinutes = sample.awakeMinutes
                record.respiratoryRate = sample.respiratoryRate
                record.sleepNeedMinutes = sample.sleepNeedMinutes
                record.disturbanceCount = sample.disturbanceCount
                record.isNap = sample.isNap
            }
        }
    }
}
