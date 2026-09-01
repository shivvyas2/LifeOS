import Foundation
import DesignSystem

/// How far back a metric's page looks, and at what grain.
///
/// The grain is not a separate choice. A year drawn as 365 bars is a smear
/// three points wide per day, and a week drawn as one bar is not a chart. Each
/// window has exactly one grain that fits the width a phone has.
enum MetricRange: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week:  "Week"
        case .month: "Month"
        case .year:  "Year"
        }
    }

    /// How many buckets the chart draws.
    var buckets: Int {
        switch self {
        case .week:  7
        case .month: 30
        case .year:  12
        }
    }

    /// A bucket is a day in the two short windows and a calendar month in the
    /// long one.
    var component: Calendar.Component {
        self == .year ? .month : .day
    }
}

/// One column of the detail chart: a bucket's reading, or the absence of one.
///
/// Distinct from `TrendPoint` because a bucket is not always a day — the year
/// view's are months — and because it carries the label the chart prints,
/// which depends on the grain rather than on the date alone.
struct MetricBar: Equatable, Identifiable {
    let date: Date
    let label: String
    let value: Double?

    var id: Date { date }
}

/// Everything a metric's page renders, as plain values.
///
/// The same rule `TodaySnapshot` follows: the view never sees a
/// `DailyMetrics`, so rendering can never fault a SwiftData object or set off
/// a fetch mid-layout.
struct MetricDetailSnapshot: Equatable {
    var metric: TodayMetric = .steps
    var range: MetricRange = .week

    /// The most recent actual reading in the window, which is usually but not
    /// always today: a night's sleep or a recovery score can be a day behind.
    var latest: Double?
    var goal: Double?

    var bars: [MetricBar] = []

    var average: Double?
    var high: Double?
    var low: Double?
    /// Days in the window that met the goal, and days that carried a reading
    /// at all. Both nil for a metric with no target, where "on target" has no
    /// meaning to report.
    var onTargetDays: Int?
    var readingDays: Int = 0

    /// True when the window holds nothing. The page says so rather than
    /// drawing an empty chart and four em dashes.
    var isEmpty: Bool { readingDays == 0 }

    /// The chart's bars, in the shape `RoundedBarChart` takes.
    var chartBars: [RoundedBarChart.Bar] {
        bars.map { RoundedBarChart.Bar(id: $0.date, label: $0.label, value: $0.value) }
    }
}
