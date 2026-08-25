import Foundation
import Persistence
import DesignSystem

/// Everything the Recovery screens render for the selected day, plus the
/// fortnight behind it.
///
/// The history is here because half these readings mean nothing alone. SpO2 of
/// 97.2 tells a reader nothing; a tenth above their own baseline does.
struct RecoverySnapshot: Equatable {
    // The day
    var recoveryPct: Double?
    var hrvMs: Double?
    var restingHR: Double?
    var dayStrain: Double?

    // Sleep quality
    var sleepMinutes: Int?
    var sleepPerformancePct: Double?
    var sleepEfficiencyPct: Double?
    var sleepConsistencyPct: Double?
    var sleepDebtMinutes: Int?

    // Vitals, each read against its own baseline
    var spo2Percentage: Double?
    var skinTempCelsius: Double?
    var respiratoryRate: Double?

    // Day totals
    var averageHR: Double?
    var maxHR: Double?
    var calories: Double?

    /// When Whoop last answered. A dead connection is otherwise indistinguishable
    /// from a quiet fortnight.
    var syncedAt: Date?

    // The fortnight
    var recoveryTrend = TrendSeries(points: [])
    var strainTrend = TrendSeries(points: [])
    var sleepTrend = TrendSeries(points: [])
    var hrvTrend = TrendSeries(points: [])
    var restingHRTrend = TrendSeries(points: [])
    var spo2Trend = TrendSeries(points: [])
    var skinTempTrend = TrendSeries(points: [])
    var respiratoryRateTrend = TrendSeries(points: [])

    /// Night by night, naps excluded. A nap is real but it is not a night, and
    /// stacking it beside one misreads the week.
    var nights: [SleepComposition] = []

    /// Vitals sitting outside the reader's own trailing baseline. Empty means
    /// quiet — either genuinely normal or not enough data to judge.
    var anomalies: [AnomalyFinding] = []

    /// startOfDay → recovery fraction (0…1) for the strip's rings.
    var weekRecovery: [Date: Double] = [:]

    /// True once anything at all has arrived, so the screens can tell "not
    /// connected" apart from "connected and quiet".
    var hasAnyReading: Bool {
        recoveryPct != nil || sleepMinutes != nil || dayStrain != nil || hrvMs != nil
    }
}
