import Foundation

public struct TrainingPlan: Equatable, Sendable {
    public let split: String
    public let minutes: Int
    public let maxIntensity: Int
    public let reason: String
    public init(split: String, minutes: Int, maxIntensity: Int, reason: String) { self.split = split; self.minutes = minutes; self.maxIntensity = maxIntensity; self.reason = reason }
}

/// Today's session from what the person wants, how much they have, and what
/// they did. Pure, so every rule is a test.
public enum WorkoutPlanner {
    static let rotation = ["push", "pull", "legs"]

    public static func plan(goal: String?, sessionMinutes: Int?, batteryPercent: Int?,
                            recentSplits: [(date: Date, split: String)], now: Date, calendar: Calendar = .current) -> TrainingPlan {
        let minutes = sessionMinutes ?? 30
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let recent = recentSplits.filter { $0.date >= weekAgo && $0.date <= now }.sorted { $0.date > $1.date }
        let hardYesterday = recent.first.map { calendar.isDate($0.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now)!) && rotation.contains($0.split) } ?? false
        let cap: Int = { switch batteryPercent { case .some(let b) where b >= 67: return 3; case .some(let b) where b >= 34: return 2; case .some: return 1; case .none: return 2 } }()

        if (batteryPercent ?? 100) <= 33 || (batteryPercent == nil && hardYesterday) {
            return TrainingPlan(split: "mobility", minutes: minutes, maxIntensity: 1, reason: "Recovery is low today, so this is a mobility day.")
        }
        switch goal {
        case "mobility": return TrainingPlan(split: "mobility", minutes: minutes, maxIntensity: cap, reason: "A mobility day, as you asked for.")
        case "endurance": return TrainingPlan(split: "cardio", minutes: minutes, maxIntensity: cap, reason: "Endurance today, paced by your battery.")
        case "strength", "hypertrophy":
            if let last = recent.first(where: { rotation.contains($0.split) }) {
                let next = rotation[(rotation.firstIndex(of: last.split)! + 1) % rotation.count]
                // `calendar.weekdaySymbols` follows the calendar's locale, which in
                // some process environments resolves to a fixed empty locale that
                // returns abbreviated names ("Mon") instead of full ones
                // ("Monday"). Force a fixed English locale for the symbol lookup so
                // the reason string is deterministic regardless of environment.
                var symbolsCalendar = calendar
                symbolsCalendar.locale = Locale(identifier: "en_US_POSIX")
                let weekday = symbolsCalendar.weekdaySymbols[calendar.component(.weekday, from: last.date) - 1]
                return TrainingPlan(split: next, minutes: minutes, maxIntensity: cap, reason: "You did \(last.split) on \(weekday), so today is \(next).")
            }
            return TrainingPlan(split: "push", minutes: minutes, maxIntensity: cap, reason: "First session this week: push.")
        default:
            return TrainingPlan(split: "full", minutes: minutes, maxIntensity: cap, reason: "Set a goal for a plan built around you.")
        }
    }
}
