import Foundation
import Persistence

/// The only thing an engine is ever given.
///
/// `DailyMetrics` is a SwiftData `@Model` class: not `Sendable`, and full of
/// raw per-source detail. `MetricsDigest` is a value type of derived numbers.
/// Because `Engine.run` takes a digest, the compiler — not a reviewer — is
/// what stops a raw health record reaching a model.
///
/// It is also the largest token lever in the system: a day is a handful of
/// numbers here, against thousands of tokens of rows.
public struct MetricsDigest: Sendable, Equatable {

    public struct Workout: Sendable, Equatable {
        public let name: String
        public let durationMinutes: Int
        public let strain: Double?
        public let averageHR: Double?
        /// Six entries, zone 0 through 5, in minutes. Nil when none were stored.
        public let zoneMinutes: [Int]?

        /// Time at or above zone three. The single most legible descriptor of a
        /// workout after strain.
        public var highZoneMinutes: Int? {
            zoneMinutes.map { $0[3] + $0[4] + $0[5] }
        }
    }

    public struct Day: Sendable, Equatable {
        public let date: Date

        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let strain: Double?
        public let steps: Int?
        public let exerciseMinutes: Int?

        public let hrvMs: Double?
        public let restingHR: Double?
        public let spo2Pct: Double?
        public let skinTempCelsius: Double?
        public let recoveryIsCalibrating: Bool?

        public let remMinutes: Int?
        public let swsMinutes: Int?
        public let lightMinutes: Int?
        public let awakeMinutes: Int?
        public let respiratoryRate: Double?
        public let sleepPerformancePct: Double?
        public let sleepEfficiencyPct: Double?
        public let sleepNeedMinutes: Int?
        public let sleepDebtMinutes: Int?
        public let needFromStrainMinutes: Int?
        /// Total nap minutes for this day, summed across every nap record. Nil
        /// when there were none, never zero: no nap at all and a nap of
        /// unrecorded length are different facts.
        public let napMinutes: Int?

        public let workouts: [Workout]
    }

    public struct Averages: Sendable, Equatable {
        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let steps: Int?
        public let hrvMs: Double?
        public let restingHR: Double?
        public let strain: Double?
        public let sleepDebtMinutes: Int?
    }

    public let days: [Day]
    public let averages: Averages

    public static func from(
        metrics: [DailyMetrics],
        sleeps: [SleepRecord],
        workouts: [WorkoutRecord],
        calendar: Calendar = .current
    ) -> MetricsDigest {
        // Naps never contribute to the night. `MetricsStore.sleepRecords`
        // records why: a nap is real, but it is not a night, and stacking it
        // beside one misreads the week.
        let nights = Dictionary(
            grouping: sleeps.filter { $0.isNap != true },
            by: { calendar.startOfDay(for: $0.attributedDate) }
        )
        let naps = Dictionary(
            grouping: sleeps.filter { $0.isNap == true },
            by: { calendar.startOfDay(for: $0.attributedDate) }
        )
        let workoutsByDay = Dictionary(
            grouping: workouts,
            by: { calendar.startOfDay(for: $0.start) }
        )

        let days = metrics
            .sorted { $0.date < $1.date }
            .map { row -> Day in
                let key = calendar.startOfDay(for: row.date)
                let night = nights[key]?.first
                let dayNaps = naps[key] ?? []

                return Day(
                    date: row.date,
                    recoveryPct: row.whoopRecoveryPct.map { Int($0.rounded()) },
                    sleepMinutes: row.sleepMinutes,
                    strain: row.whoopDayStrain,
                    steps: row.steps,
                    exerciseMinutes: row.exerciseMinutes,
                    hrvMs: row.hrvMs,
                    restingHR: row.restingHR,
                    spo2Pct: row.spo2Percentage,
                    skinTempCelsius: row.skinTempCelsius,
                    recoveryIsCalibrating: row.whoopRecoveryIsCalibrating,
                    remMinutes: night?.remMinutes,
                    swsMinutes: night?.swsMinutes,
                    lightMinutes: night?.lightMinutes,
                    awakeMinutes: night?.awakeMinutes,
                    respiratoryRate: row.respiratoryRate,
                    sleepPerformancePct: row.whoopSleepPerformancePct,
                    sleepEfficiencyPct: row.whoopSleepEfficiencyPct,
                    sleepNeedMinutes: night?.sleepNeedMinutes,
                    sleepDebtMinutes: row.whoopSleepDebtMinutes,
                    needFromStrainMinutes: night?.needFromStrainMinutes,
                    // Nil, not zero, when the day had no nap at all.
                    napMinutes: dayNaps.isEmpty
                        ? nil
                        : dayNaps.reduce(0) { $0 + $1.durationMinutes },
                    workouts: (workoutsByDay[key] ?? []).map { w in
                        Workout(
                            name: w.activityName,
                            durationMinutes: w.durationMinutes,
                            strain: w.strain,
                            averageHR: w.averageHR,
                            zoneMinutes: [
                                w.zoneZeroMinutes, w.zoneOneMinutes, w.zoneTwoMinutes,
                                w.zoneThreeMinutes, w.zoneFourMinutes, w.zoneFiveMinutes
                            ].contains(where: { $0 != nil })
                                ? [w.zoneZeroMinutes ?? 0, w.zoneOneMinutes ?? 0,
                                   w.zoneTwoMinutes ?? 0, w.zoneThreeMinutes ?? 0,
                                   w.zoneFourMinutes ?? 0, w.zoneFiveMinutes ?? 0]
                                : nil
                        )
                    }
                )
            }

        return MetricsDigest(
            days: days,
            averages: Averages(
                recoveryPct: average(days.compactMap(\.recoveryPct)),
                sleepMinutes: average(days.compactMap(\.sleepMinutes)),
                steps: average(days.compactMap(\.steps)),
                hrvMs: average(days.compactMap(\.hrvMs)),
                restingHR: average(days.compactMap(\.restingHR)),
                strain: average(days.compactMap(\.strain)),
                sleepDebtMinutes: average(days.compactMap(\.sleepDebtMinutes))
            )
        )
    }

    /// Nil rather than zero when nothing contributed: an average of no
    /// readings is not an average of zero.
    private static func average(_ values: [Int]) -> Int? {
        guard values.isEmpty == false else { return nil }
        return values.reduce(0, +) / values.count
    }

    /// Nil rather than zero when nothing contributed: an average of no
    /// readings is not an average of zero.
    private static func average(_ values: [Double]) -> Double? {
        guard values.isEmpty == false else { return nil }
        return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }

    /// The digest as the model sees it. One line per day, omitting anything
    /// missing rather than writing "nil" — a blank costs no tokens and says
    /// the same thing.
    public var promptLines: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"

        return days.map { day in
            var parts: [String] = [formatter.string(from: day.date)]
            if let v = day.recoveryPct { parts.append("recovery \(v)%") }
            if let v = day.sleepMinutes { parts.append("sleep \(v / 60)h\(v % 60)m") }
            if let v = day.strain { parts.append("strain \(String(format: "%.1f", v))") }
            if let v = day.steps { parts.append("steps \(v)") }
            if let v = day.exerciseMinutes { parts.append("exercise \(v)m") }
            return parts.joined(separator: ", ")
        }
        .joined(separator: "\n")
    }
}
