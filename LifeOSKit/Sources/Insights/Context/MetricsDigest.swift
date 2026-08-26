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

    /// Who the render is for. The distinction exists because the raw Whoop
    /// series stays on the phone: on-device inference sends nothing anywhere,
    /// and a provider call does.
    ///
    /// Nothing in production selects `.offDevice` today. `CoachTask.prompt`
    /// has no audience parameter and reaches this type through
    /// `promptLines`, which defaults to `.onDevice`, so this case is
    /// exercised only by tests. It is a mechanism waiting to be wired, not
    /// one currently protecting anything: a remote engine built before the
    /// wiring exists would still get the on-device render.
    public enum Audience: Sendable {
        case onDevice
        case offDevice
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

    /// The digest as the model sees it. One block per day, omitting anything
    /// missing rather than writing "nil": a blank costs no tokens and says the
    /// same thing. Deltas against the baseline are what let the model tell a
    /// number from an unusual number.
    public var promptLines: String { promptLines(for: .onDevice) }

    /// Characters, not tokens. The on-device context window is believed to be
    /// 4096 tokens, but that figure is not verified against the SDK, and a
    /// character budget plus a size-pinning test catches regressions without
    /// depending on it being right. At roughly four characters per token this
    /// leaves room for instructions, the generation schema, the question and
    /// the output allocation.
    public static let promptBudget = 6_000

    public func promptLines(for audience: Audience, budget: Int = MetricsDigest.promptBudget) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"

        // Whole days are dropped rather than fields trimmed, so a day that
        // renders at all renders completely. Oldest goes first: the newest day
        // is the one a brief is about.
        var window = days
        while true {
            let text = assemble(window, formatter, audience)
            if text.count <= budget || window.count <= 1 { return text }
            window.removeFirst()
        }
    }

    private func assemble(_ window: [Day], _ formatter: DateFormatter, _ audience: Audience) -> String {
        var blocks: [String] = []
        if let baseline = baselineLine(for: audience) { blocks.append(baseline + "\n") }
        blocks.append(contentsOf: window.map { render($0, formatter, audience) })
        return blocks.joined(separator: "\n")
    }

    private func baselineLine(for audience: Audience) -> String? {
        var parts: [String] = []
        if let v = averages.recoveryPct { parts.append("recovery \(v)%") }
        if let v = averages.sleepMinutes { parts.append("sleep \(duration(v))") }
        if audience == .onDevice, let v = averages.hrvMs { parts.append("hrv \(number(v))ms") }
        if let v = averages.restingHR { parts.append("rhr \(number(v))") }
        if let v = averages.strain { parts.append("strain \(number(v))") }
        if let v = averages.steps { parts.append("steps \(v)") }
        guard parts.isEmpty == false else { return nil }
        return "\(days.count)-day baseline: " + parts.joined(separator: ", ")
    }

    private func render(_ day: Day, _ formatter: DateFormatter, _ audience: Audience) -> String {
        var parts: [String] = [formatter.string(from: day.date)]

        if let v = day.recoveryPct {
            var text = "recovery \(v)%\(delta(v, averages.recoveryPct))"
            // A score produced while Whoop is calibrating is not a score that
            // supports a comparison. Marking it is strictly more information
            // than dropping it.
            if day.recoveryIsCalibrating == true { text += " (calibrating)" }
            parts.append(text)
        }
        if let v = day.sleepMinutes {
            var text = "sleep \(duration(v))\(deltaMinutes(v, averages.sleepMinutes))"
            if let need = day.sleepNeedMinutes { text += " of \(duration(need)) needed" }
            parts.append(text)
        }
        if let v = day.sleepDebtMinutes { parts.append("debt \(signed(v))m") }
        if let v = day.needFromStrainMinutes { parts.append("from strain \(signed(v))m") }
        if let v = day.sleepPerformancePct { parts.append("perf \(number(v))%") }
        if let v = day.sleepEfficiencyPct { parts.append("eff \(number(v))%") }
        if let v = day.remMinutes { parts.append("rem \(duration(v))") }
        if let v = day.swsMinutes { parts.append("sws \(duration(v))") }
        if let v = day.lightMinutes { parts.append("light \(duration(v))") }
        if let v = day.awakeMinutes { parts.append("awake \(duration(v))") }
        if let v = day.napMinutes { parts.append("nap \(duration(v))") }
        if let v = day.strain { parts.append("strain \(number(v))\(delta(v, averages.strain))") }
        if audience == .onDevice {
            if let v = day.hrvMs { parts.append("hrv \(number(v))ms\(delta(v, averages.hrvMs))") }
            if let v = day.spo2Pct { parts.append("spo2 \(number(v))%") }
            if let v = day.skinTempCelsius { parts.append("skin \(number(v))C") }
            if let v = day.respiratoryRate { parts.append("resp \(number(v))") }
        }
        if let v = day.restingHR { parts.append("rhr \(number(v))\(delta(v, averages.restingHR))") }
        if let v = day.steps { parts.append("steps \(v)") }
        if let v = day.exerciseMinutes { parts.append("exercise \(v)m") }

        var block = parts.joined(separator: ", ")
        for workout in day.workouts {
            var w = ["workout: \(workout.name) \(workout.durationMinutes)m"]
            if let v = workout.strain { w.append("strain \(number(v))") }
            if let v = workout.averageHR { w.append("avg HR \(number(v))") }
            if let v = workout.highZoneMinutes, v > 0 { w.append("zone 3+ \(v)m") }
            block += "\n  " + w.joined(separator: ", ")
        }
        return block
    }

    // Formatting helpers. Kept private and tiny: the render is the only caller.

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
                      : "\(minutes)m"
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    /// Empty when there is no baseline to compare against, so a delta never
    /// implies a comparison that was not made.
    private func delta(_ value: Int, _ average: Int?) -> String {
        guard let average, average != value else { return "" }
        return " (\(signed(value - average)))"
    }

    private func delta(_ value: Double, _ average: Double?) -> String {
        guard let average else { return "" }
        let difference = ((value - average) * 10).rounded() / 10
        guard difference != 0 else { return "" }
        return difference > 0 ? " (+\(number(difference)))" : " (\(number(difference)))"
    }

    private func deltaMinutes(_ value: Int, _ average: Int?) -> String {
        guard let average, average != value else { return "" }
        let difference = value - average
        return " (\(difference >= 0 ? "+" : "-")\(duration(abs(difference))))"
    }
}
