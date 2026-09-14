import Foundation
import Persistence

/// App-defined comparison scores. These are not vendor strain/recovery scores.
public struct SocialWellnessDay: Codable, Sendable, Equatable {
    public let day: String
    public let effort: Int?
    public let recharge: Int?
    public let rest: Int?
    public let effortSource: String?
    public let rechargeSource: String?
    public let restSource: String?
    public let observedAt: Date
    enum CodingKeys: String, CodingKey {
        case day, effort, recharge, rest
        case effortSource = "effort_source", rechargeSource = "recharge_source", restSource = "rest_source", observedAt = "observed_at"
    }
    public init(day: String, effort: Int?, recharge: Int?, rest: Int?, effortSource: String?, rechargeSource: String?, restSource: String?, observedAt: Date) {
        self.day = day; self.effort = effort; self.recharge = recharge; self.rest = rest
        self.effortSource = effortSource; self.rechargeSource = rechargeSource; self.restSource = restSource; self.observedAt = observedAt
    }
}

public struct WellnessReading: Sendable {
    public let date: Date
    public let exerciseMinutes: Int?
    public let sleepMinutes: Int?
    public let hrv: Double?
    public let restingHR: Double?
    public let sources: [String: String]
    public let calibrating: Bool
    public let observedAt: Date
    public init(date: Date, exerciseMinutes: Int? = nil, sleepMinutes: Int? = nil, hrv: Double? = nil,
                restingHR: Double? = nil, sources: [String: String], calibrating: Bool = false, observedAt: Date? = nil) {
        self.date = date; self.exerciseMinutes = exerciseMinutes; self.sleepMinutes = sleepMinutes
        self.hrv = hrv; self.restingHR = restingHR; self.sources = sources; self.calibrating = calibrating; self.observedAt = observedAt ?? date
    }
    @MainActor public init(_ row: DailyMetrics) {
        self.init(date: row.date, exerciseMinutes: row.exerciseMinutes, sleepMinutes: row.sleepMinutes,
                  hrv: row.hrvMs, restingHR: row.restingHR, sources: row.sources,
                  calibrating: row.whoopRecoveryIsCalibrating == true, observedAt: row.updatedAt)
    }
}

public enum SocialWellness {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    /// Uses the selected source once, never sums duplicate readings across providers.
    /// Only today/yesterday are published, with a 28-day, same-source personal baseline.
    public static func scores(readings: [WellnessReading], exerciseGoal: Int, sleepGoal: Int,
                              now: Date = .now, calendar: Calendar = .current) -> [SocialWellnessDay] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        // A duplicated date must not inflate the baseline's seven-day requirement.
        let unique = Dictionary(grouping: readings, by: { calendar.startOfDay(for: $0.date) })
            .compactMap { $0.value.max(by: { $0.observedAt < $1.observedAt }) }
        return unique.filter { $0.date >= yesterday && $0.date < calendar.date(byAdding: .day, value: 1, to: today)! }
            .sorted { $0.date < $1.date }.map { row in
                let effortSource = source(row, .exerciseMinutes)
                let restSource = source(row, .sleepMinutes)
                let effort = effortSource == nil ? nil : progress(row.exerciseMinutes, goal: exerciseGoal)
                let rest = restSource == nil ? nil : progress(row.sleepMinutes, goal: sleepGoal)
                let rechargeSource = source(row, .hrvMs)
                let recharge = rechargeScore(row, readings: unique, calendar: calendar)
                return SocialWellnessDay(day: dayKey(row.date, calendar: calendar), effort: effort, recharge: recharge, rest: rest,
                    effortSource: effort == nil ? nil : effortSource, rechargeSource: recharge == nil ? nil : rechargeSource,
                    restSource: rest == nil ? nil : restSource, observedAt: row.observedAt)
            }
    }
    private static func source(_ row: WellnessReading, _ metric: HealthMetric) -> String? {
        guard let raw = row.sources[metric.rawValue], ["appleHealth", "whoop", "fitbit"].contains(raw) else { return nil }
        return raw
    }
    private static func progress(_ minutes: Int?, goal: Int) -> Int? {
        guard let minutes, (0...1440).contains(minutes), goal > 0, goal <= 1440 else { return nil }
        return min(100, Int((Double(minutes) / Double(goal) * 100).rounded()))
    }
    private static func rechargeScore(_ row: WellnessReading, readings: [WellnessReading], calendar: Calendar) -> Int? {
        guard let provider = source(row, .hrvMs), provider == source(row, .restingHR),
              !(provider == "whoop" && row.calibrating),
              let hrv = row.hrv, hrv.isFinite, hrv > 0, hrv <= 500,
              let rhr = row.restingHR, rhr.isFinite, (20...150).contains(rhr) else { return nil }
        let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: row.date))!
        let baseline = readings.filter { item in
            item.date >= start && item.date < calendar.startOfDay(for: row.date)
                && source(item, .hrvMs) == provider && source(item, .restingHR) == provider
                && !(provider == "whoop" && item.calibrating)
                && item.hrv.map { $0.isFinite && $0 > 0 && $0 <= 500 } == true
                && item.restingHR.map { $0.isFinite && (20...150).contains($0) } == true
        }
        guard baseline.count >= 7 else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted(); let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        let usualHRV = median(baseline.compactMap(\.hrv))
        let usualRHR = median(baseline.compactMap(\.restingHR))
        // 50 is the personal baseline. This transparent estimate is not a
        // recovery percentage, a clinical assessment, or a vendor score.
        let value = 50 + 100 * (0.6 * (hrv / usualHRV - 1) + 0.4 * (1 - rhr / usualRHR))
        return Int(min(100, max(0, value)).rounded())
    }
}
