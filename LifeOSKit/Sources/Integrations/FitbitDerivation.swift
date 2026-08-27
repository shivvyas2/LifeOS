import Foundation
import SwiftData
import Persistence

/// Rolls Fitbit payloads into the daily spine.
///
/// Split in two on purpose: `days(from:)` is pure and turns payloads into
/// values, and `derive` writes them. The mapping is the part that can be
/// perfectly decoded and still land in the wrong column, and a pure function
/// is where that is cheapest to pin.
///
/// Every write goes through `MetricArbiter`, so Fitbit wins or fills a gap by
/// rank rather than by whichever sync happened to run last.
@MainActor
public struct FitbitDerivation {
    private let store: MetricsStore
    private let ranking: SourceRanking
    private let calendar: Calendar

    public init(
        store: MetricsStore,
        ranking: SourceRanking = SourceRanking(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.ranking = ranking
        self.calendar = calendar
    }

    public func derive(_ payloads: FitbitPayloads) throws {
        let days = Self.days(from: payloads, calendar: calendar)
        guard !days.isEmpty else { return }

        try store.upsertBatch(dates: days.map(\.date)) { date, row in
            let day = calendar.startOfDay(for: date)
            guard let reading = days.first(where: { $0.date == day }) else { return }

            for (metric, value) in reading.values {
                write(merged(metric, incoming: value, existing: existing(metric, in: row), row: row),
                      for: metric, into: row)
            }
            row.syncedAt = .now
        }
    }

    // MARK: - The pure half

    /// Fitbit sends `yyyy-MM-dd` in the user's own local time, with no zone.
    ///
    /// Parsed with a fixed POSIX locale and the current time zone, then reduced
    /// to a start of day. An ISO8601 parser treats these as UTC midnight, which
    /// shifts every night by a day for anyone west of UTC: the sleep that
    /// belongs to Tuesday lands on Monday, and the whole week reads wrong.
    static func parseDay(_ text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text).map { calendar.startOfDay(for: $0) }
    }

    /// Fitbit reports VO2 max as either "46" or a range like "40-44".
    /// A range becomes its midpoint, because storing the lower bound would
    /// understate every GPS-less reading.
    static func parseVO2Max(_ text: String) -> Double? {
        let parts = text.split(separator: "-").compactMap { Double($0) }
        switch parts.count {
        case 1: return parts[0]
        case 2: return (parts[0] + parts[1]) / 2
        default: return nil
        }
    }

    public static func days(from payloads: FitbitPayloads, calendar: Calendar = .current) -> [FitbitDay] {
        var byDay: [Date: [HealthMetric: Double]] = [:]

        func put(_ day: Date?, _ metric: HealthMetric, _ value: Double?) {
            guard let day, let value else { return }
            byDay[day, default: [:]][metric] = value
        }

        for night in payloads.sleep?.sleep ?? [] {
            let day = parseDay(night.dateOfSleep, calendar: calendar)
            put(day, .sleepMinutes, night.minutesAsleep)
            put(day, .awakeMinutes, night.minutesAwake)
            put(day, .timeInBedMinutes, night.timeInBed)
            put(day, .sleepEfficiencyPercentage, night.efficiency)
            put(day, .deepSleepMinutes, night.levels?.summary.deep?.minutes)
            put(day, .remSleepMinutes, night.levels?.summary.rem?.minutes)
            // Fitbit calls it light and Apple calls it core. The same stage
            // under two vendors' names, and filing Fitbit's light anywhere
            // else leaves the sleep panel with a blank row and a total that
            // does not add up.
            put(day, .coreSleepMinutes, night.levels?.summary.light?.minutes)
        }

        for entry in payloads.hrv?.hrv ?? [] {
            // dailyRmssd only. deepRmssd measures a different thing over a
            // different window, so averaging the two would produce a number
            // Fitbit never reported. It is kept as its own extra instead.
            put(parseDay(entry.dateTime, calendar: calendar), .hrvMs, entry.value.dailyRmssd)
        }

        for entry in payloads.spo2 ?? [] {
            put(parseDay(entry.dateTime, calendar: calendar), .spo2Percentage, entry.value.avg)
        }

        for entry in payloads.breathing?.br ?? [] {
            put(parseDay(entry.dateTime, calendar: calendar), .respiratoryRate, entry.value.breathingRate)
        }

        for entry in payloads.skinTemperature?.tempSkin ?? [] {
            put(parseDay(entry.dateTime, calendar: calendar),
                .wristTemperatureCelsius, entry.value.nightlyRelative)
        }

        for entry in payloads.restingHeartRate?.days ?? [] {
            put(parseDay(entry.dateTime, calendar: calendar), .restingHR, entry.value.restingHeartRate)
        }

        for entry in payloads.cardioFitness?.cardioScore ?? [] {
            put(parseDay(entry.dateTime, calendar: calendar),
                .vo2Max, entry.value.vo2Max.flatMap(parseVO2Max))
        }

        return byDay
            .map { FitbitDay(date: $0.key, values: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Writing

    private func merged(
        _ metric: HealthMetric, incoming: Double?, existing: Double?, row: DailyMetrics
    ) -> Double? {
        let held = row.source(metric.rawValue).flatMap(MetricSource.init(rawValue:))
        let outcome = MetricArbiter.resolve(
            metric: metric,
            existing: existing, existingSource: held,
            incoming: incoming, incomingSource: .fitbit,
            ranking: ranking
        )
        row.setSource(metric.rawValue, outcome.source?.rawValue)
        return outcome.value
    }

    private func existing(_ metric: HealthMetric, in row: DailyMetrics) -> Double? {
        switch metric {
        case .sleepMinutes:      row.sleepMinutes.map(Double.init)
        case .restingHR:         row.restingHR
        case .hrvMs:             row.hrvMs
        case .spo2Percentage:    row.spo2Percentage
        case .respiratoryRate:   row.respiratoryRate
        default:                 row.extra(metric.rawValue)
        }
    }

    private func write(_ value: Double?, for metric: HealthMetric, into row: DailyMetrics) {
        switch metric {
        case .sleepMinutes:      row.sleepMinutes = value.map { Int($0.rounded()) }
        case .restingHR:         row.restingHR = value
        case .hrvMs:             row.hrvMs = value
        case .spo2Percentage:    row.spo2Percentage = value
        case .respiratoryRate:   row.respiratoryRate = value
        default:                 row.setExtra(metric.rawValue, value)
        }
    }
}
