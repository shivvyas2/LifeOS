import Foundation
import SwiftData
import Persistence
import DesignSystem

@MainActor @Observable
final class RecoveryViewModel {
    private(set) var snapshot = RecoverySnapshot()
    var selectedDate: Date = .now

    /// The window every trend and baseline is computed over. Matches the sync
    /// window, so a chart never has a gap the sync could have filled.
    private static let windowDays = 14

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func select(_ date: Date) {
        selectedDate = date
        load()
    }

    func load() {
        guard let context else { return }
        let store = MetricsStore(context: context, calendar: calendar)

        do {
            let end = selectedDate
            let start = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: end) ?? end

            // One fetch for the whole window. The selected day is picked out of
            // it rather than fetched again.
            let rows = try store.metrics(from: start, to: end)
            let day = rows.first { calendar.isDate($0.date, inSameDayAs: end) }

            let nights = try store.sleepRecords(from: start, to: end, includingNaps: false)
                .map {
                    SleepComposition(
                        date: $0.attributedDate,
                        lightMinutes: $0.lightMinutes,
                        remMinutes: $0.remMinutes,
                        swsMinutes: $0.swsMinutes,
                        awakeMinutes: $0.awakeMinutes
                    )
                }
                // A night with nothing recorded would draw as a zero-height bar,
                // which reads as "you did not sleep".
                .filter(\.isRenderable)

            snapshot = RecoverySnapshot(
                recoveryPct: day?.whoopRecoveryPct,
                hrvMs: day?.hrvMs,
                restingHR: day?.restingHR,
                dayStrain: day?.whoopDayStrain,

                sleepMinutes: day?.sleepMinutes,
                sleepPerformancePct: day?.whoopSleepPerformancePct,
                sleepEfficiencyPct: day?.whoopSleepEfficiencyPct,
                sleepConsistencyPct: day?.whoopSleepConsistencyPct,
                sleepDebtMinutes: day?.whoopSleepDebtMinutes,

                spo2Percentage: day?.spo2Percentage,
                skinTempCelsius: day?.skinTempCelsius,
                respiratoryRate: day?.respiratoryRate,

                averageHR: day?.whoopAverageHR,
                maxHR: day?.whoopMaxHR,
                calories: day?.whoopCalories,

                syncedAt: day?.syncedAt,

                recoveryTrend: trend(rows, from: start, to: end) { $0.whoopRecoveryPct },
                strainTrend: trend(rows, from: start, to: end) { $0.whoopDayStrain },
                sleepTrend: trend(rows, from: start, to: end) { $0.sleepMinutes.map(Double.init) },
                hrvTrend: trend(rows, from: start, to: end) { $0.hrvMs },
                restingHRTrend: trend(rows, from: start, to: end) { $0.restingHR },
                spo2Trend: trend(rows, from: start, to: end) { $0.spo2Percentage },
                skinTempTrend: trend(rows, from: start, to: end) { $0.skinTempCelsius },
                respiratoryRateTrend: trend(rows, from: start, to: end) { $0.respiratoryRate },

                nights: nights
            )
        } catch {
            assertionFailure("Recovery load failed: \(error)")
        }
    }

    /// Builds a point for every day in the window, not just the days with rows.
    /// A day Whoop never reported has to stay a gap in the chart, and a series
    /// built only from existing rows would silently close it.
    private func trend(
        _ rows: [DailyMetrics], from start: Date, to end: Date,
        value: (DailyMetrics) -> Double?
    ) -> TrendSeries {
        var byDay: [Date: DailyMetrics] = [:]
        for row in rows { byDay[calendar.startOfDay(for: row.date)] = row }

        var points: [TrendPoint] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            points.append(TrendPoint(date: day, value: byDay[day].flatMap(value)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return TrendSeries(points: points)
    }
}
