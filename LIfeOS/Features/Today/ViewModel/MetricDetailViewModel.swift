import Foundation
import SwiftData
import DesignSystem
import Persistence

/// One metric's history, at whichever grain the range asks for.
///
/// A view model of its own rather than more fields on `TodayViewModel`: that
/// one runs a ~400-day pass over every row to build the dot grid and the
/// streak, and it runs on every save in the app. Hanging a year of bucketing
/// off it would repeat that work for a screen nobody is looking at.
@MainActor @Observable
final class MetricDetailViewModel {
    private(set) var snapshot = MetricDetailSnapshot()

    /// Which window is showing. Set by the picker; the reload is driven from
    /// the screen so the store is read once per change rather than once per
    /// render.
    var range: MetricRange = .week

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    /// Rebuilds the snapshot for `metric` over the current range.
    ///
    /// Safe to call on every save: the window is bounded by the range, so the
    /// worst case is a year of rows rather than the whole table.
    func load(_ metric: TodayMetric, now: Date = .now) {
        guard let context else { return }
        let store = MetricsStore(context: context, calendar: calendar)

        do {
            let targets = try store.goals().targets
            let goal = metric.goal(in: targets)
            let buckets = Self.buckets(range: range, endingOn: now, calendar: calendar)
            guard let start = buckets.first else { return }

            // One fetch, then bucketed here. A fetch per bucket would be
            // twelve round trips for the year view.
            let rows = try store.metrics(from: start, to: now)

            var readingsByBucket: [Date: [Double]] = [:]
            readingsByBucket.reserveCapacity(buckets.count)
            for row in rows {
                guard let value = metric.value(in: row),
                      let bucket = Self.bucket(for: row.date, range: range, calendar: calendar)
                else { continue }
                readingsByBucket[bucket, default: []].append(value)
            }

            // A day has at most one row, so the mean is that row's own value in
            // the two short windows. It only averages anything in the year
            // view, where a bucket is a month of days.
            let bars = buckets.map { bucket in
                MetricBar(
                    date: bucket,
                    label: Self.label(for: bucket, range: range, calendar: calendar),
                    value: readingsByBucket[bucket].map { $0.reduce(0, +) / Double($0.count) }
                )
            }

            let readings = bars.compactMap(\.value)
            snapshot = MetricDetailSnapshot(
                metric: metric,
                range: range,
                // The last bar with a reading, not the last bar: the window
                // usually ends on a day Whoop has not scored yet, and reading
                // "—" as the headline figure for a metric with a week behind
                // it is the screen looking broken.
                latest: bars.reversed().first(where: { $0.value != nil })?.value ?? nil,
                goal: goal,
                bars: bars,
                average: readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count),
                high: readings.max(),
                low: readings.min(),
                onTargetDays: goal.map { target in readings.filter { $0 >= target }.count },
                readingDays: readings.count
            )
        } catch {
            // A read failure leaves the previous snapshot in place rather than
            // blanking the page. Nothing here is recoverable by the user.
            assertionFailure("Metric detail load failed: \(error)")
        }
    }

    // MARK: - Bucketing

    /// The buckets the range covers, oldest first, every one present whether or
    /// not a reading exists for it.
    ///
    /// Gaps are kept for `TrendSeries.days`' reason: compacting the buckets
    /// that do have readings draws a chart whose neighbouring bars are not a
    /// bucket apart, which is a quieter lie than a false zero but a lie.
    static func buckets(range: MetricRange, endingOn date: Date, calendar: Calendar) -> [Date] {
        let end = anchor(for: date, range: range, calendar: calendar)
        return (0..<range.buckets).reversed().compactMap {
            calendar.date(byAdding: range.component, value: -$0, to: end)
        }
    }

    /// Which bucket a day falls in: the day itself, or the first of its month.
    static func bucket(for date: Date, range: MetricRange, calendar: Calendar) -> Date? {
        anchor(for: date, range: range, calendar: calendar)
    }

    private static func anchor(for date: Date, range: MetricRange, calendar: Calendar) -> Date {
        guard range == .year else { return calendar.startOfDay(for: date) }
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
    }

    /// What is printed under a bar.
    ///
    /// Thirty labelled bars on a phone is a grey smudge, so the month view
    /// prints one in five and leaves the rest blank. The bars are still all
    /// there; only the ruler is thinned.
    static func label(for date: Date, range: MetricRange, calendar: Calendar) -> String {
        switch range {
        case .week:
            let weekday = calendar.component(.weekday, from: date)
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
        case .month:
            let day = calendar.component(.day, from: date)
            return day % 5 == 0 ? "\(day)" : ""
        case .year:
            let month = calendar.component(.month, from: date)
            let symbols = calendar.veryShortStandaloneMonthSymbols
            return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
        }
    }
}
