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
}
