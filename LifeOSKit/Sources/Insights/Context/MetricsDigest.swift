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

    public struct Day: Sendable, Equatable {
        public let date: Date
        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let strain: Double?
        public let steps: Int?
        public let exerciseMinutes: Int?
    }

    public struct Averages: Sendable, Equatable {
        public let recoveryPct: Int?
        public let sleepMinutes: Int?
        public let steps: Int?
    }

    public let days: [Day]
    public let averages: Averages

    public static func from(_ rows: [DailyMetrics]) -> MetricsDigest {
        let days = rows
            .sorted { $0.date < $1.date }
            .map { row in
                Day(
                    date: row.date,
                    recoveryPct: row.whoopRecoveryPct.map { Int($0.rounded()) },
                    sleepMinutes: row.sleepMinutes,
                    strain: row.whoopDayStrain,
                    steps: row.steps,
                    exerciseMinutes: row.exerciseMinutes
                )
            }

        return MetricsDigest(
            days: days,
            averages: Averages(
                recoveryPct: average(days.compactMap(\.recoveryPct)),
                sleepMinutes: average(days.compactMap(\.sleepMinutes)),
                steps: average(days.compactMap(\.steps))
            )
        )
    }

    /// Nil rather than zero when nothing contributed: an average of no
    /// readings is not an average of zero.
    private static func average(_ values: [Int]) -> Int? {
        guard values.isEmpty == false else { return nil }
        return values.reduce(0, +) / values.count
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
