import Foundation
import DesignSystem

/// Everything the Today screen renders, as plain values.
///
/// The view never sees a `DailyMetrics`, so rendering can never fault a
/// SwiftData object or trigger a fetch mid-layout.
struct TodaySnapshot: Equatable {
    var date: Date = .now
    var cells: [DotCell] = []
    var streak: Int = 0

    var steps: Int?
    var stepsProgress: Double?
    var sleepMinutes: Int?
    var sleepProgress: Double?
    var weightKg: Double?
    var recoveryPct: Double?

    /// The last seven days behind each figure, most recent last, with a slot
    /// for every day so a gap stays a gap in the chart rather than closing up.
    var stepsWeek: TrendSeries = TrendSeries(points: [])
    var sleepWeek: TrendSeries = TrendSeries(points: [])
    var weightWeek: TrendSeries = TrendSeries(points: [])
    var recoveryWeek: TrendSeries = TrendSeries(points: [])

    /// The goals the week is judged against, so a day that hit its target can
    /// be drawn differently from one that did not.
    var stepsTarget: Double?
    var sleepTargetMinutes: Double?
}
