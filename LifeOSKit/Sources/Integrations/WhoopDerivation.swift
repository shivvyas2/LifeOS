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
        cycles: [WhoopCycleSample] = [],
        workouts: [WhoopWorkoutSample] = []
    ) throws {
        try storeSleepRecords(sleeps)
        try storeWorkoutRecords(workouts)

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
        // A day with only a workout still needs a row of its own.
        for sample in workouts {
            let day = calendar.startOfDay(for: sample.start)
            if byDay[day] == nil { byDay[day] = (nil, nil, nil) }
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

            let dayWorkouts = workouts.filter { calendar.startOfDay(for: $0.start) == day }
            if !dayWorkouts.isEmpty {
                row.exerciseMinutes = dayWorkouts.reduce(0) { $0 + $1.durationMinutes }
            }

            row.syncedAt = .now
        }
    }

    /// Rebuilds every metric row from the archive, with no network call. This is
    /// the capability the archive exists for: a derivation bug found months from
    /// now is fixable without asking Whoop for the data again.
    @discardableResult
    public func rederive() throws -> Int {
        // Mapping lives once, on the DTOs themselves (`WhoopClient.swift`), so the
        // live client and this rebuild path cannot drift apart the way they did
        // before: a field added to one copy and not the other silently degraded
        // a rebuilt row relative to a synced one.
        let recoveries = try decode(kind: "recovery", as: WhoopDTOs.RecoveryRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map(\.sample)

        let cycles = try decode(kind: "cycle", as: WhoopDTOs.CycleRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map(\.sample)

        let sleeps = try decode(kind: "sleep", as: WhoopDTOs.SleepRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .map(\.sample)

        let workouts = try decode(kind: "workout", as: WhoopDTOs.WorkoutRecord.self)
            .filter { WhoopDTOs.isScored($0.score_state) }
            .compactMap(\.sample)

        try derive(recoveries: recoveries, sleeps: sleeps, cycles: cycles, workouts: workouts)

        var days = Set<Date>()
        for sample in recoveries { days.insert(calendar.startOfDay(for: sample.date)) }
        for sample in cycles { days.insert(calendar.startOfDay(for: sample.date)) }
        for sample in sleeps where !sample.isNap {
            days.insert(WhoopAttribution.day(forSleepEndingAt: sample.end, calendar: calendar))
        }
        for sample in workouts { days.insert(calendar.startOfDay(for: sample.start)) }
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
                // Nil never overwrites a stored value, matching `derive` above: a
                // re-sync where Whoop omits a sub-field must not wipe a reading a
                // previous, more complete sync already stored.
                if let value = sample.performancePercentage { record.performancePercentage = value }
                if let value = sample.consistencyPercentage { record.consistencyPercentage = value }
                if let value = sample.efficiencyPercentage { record.efficiencyPercentage = value }
                if let value = sample.lightMinutes { record.lightMinutes = value }
                if let value = sample.remMinutes { record.remMinutes = value }
                if let value = sample.swsMinutes { record.swsMinutes = value }
                if let value = sample.awakeMinutes { record.awakeMinutes = value }
                if let value = sample.noDataMinutes { record.noDataMinutes = value }
                if let value = sample.sleepCycleCount { record.sleepCycleCount = value }
                if let value = sample.respiratoryRate { record.respiratoryRate = value }
                if let value = sample.sleepNeedMinutes { record.sleepNeedMinutes = value }
                if let value = sample.sleepDebtMinutes { record.sleepDebtMinutes = value }
                if let value = sample.disturbanceCount { record.disturbanceCount = value }
                record.isNap = sample.isNap
            }
        }
    }

    private func storeWorkoutRecords(_ workouts: [WhoopWorkoutSample]) throws {
        for sample in workouts {
            try store.upsertWorkoutRecord(
                externalID: sample.externalID,
                start: sample.start,
                durationMinutes: sample.durationMinutes,
                activityName: sample.sportName
            ) { record in
                // Nil never overwrites a stored value, matching the sleep and day
                // rows above.
                if let value = sample.energyKcal { record.energyKcal = value }
                if let value = sample.strain { record.strain = value }
                if let value = sample.averageHR { record.averageHR = value }
                if let value = sample.maxHR { record.maxHR = value }
                if let value = sample.percentRecorded { record.percentRecorded = value }
                if let value = sample.distanceMeters { record.distanceMeters = value }
                if let value = sample.altitudeGainMeters { record.altitudeGainMeters = value }
                if let value = sample.altitudeChangeMeters { record.altitudeChangeMeters = value }
                if let value = sample.sportID { record.sportID = value }
            }
        }
    }
}
