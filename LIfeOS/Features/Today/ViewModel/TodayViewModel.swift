import Foundation
import SwiftData
import DesignSystem
import Persistence

@MainActor @Observable
final class TodayViewModel {
    private(set) var snapshot = TodaySnapshot()

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    /// One pass over the day rows: the day→status map is built once and used
    /// for both the grid and the streak. Rebuilding it inside the per-day
    /// closure would re-evaluate every row about thirty times per load.
    func load() {
        guard let context else { return }
        let store = MetricsStore(context: context, calendar: calendar)

        do {
            let targets = try store.goals().targets

            // Bounded: the grid needs this month and the streak needs recent
            // history, never the whole table.
            let start = calendar.date(byAdding: .day, value: -400, to: .now) ?? .distantPast
            let rows = try store.metrics(from: start, to: .now)

            var statusByDay: [Date: DayStatus] = [:]
            statusByDay.reserveCapacity(rows.count)
            var ordered: [DayStatus] = []
            ordered.reserveCapacity(rows.count)

            for row in rows {
                let status = evaluate(row.reading, against: targets)
                statusByDay[calendar.startOfDay(for: row.date)] = status
                ordered.append(status)      // rows are already most-recent-first
            }

            let cells = MonthGridLayout.cells(
                monthContaining: .now,
                calendar: calendar,
                today: .now,
                status: { date in
                    switch statusByDay[calendar.startOfDay(for: date)] {
                    case .onTarget: .onTarget
                    case .missed:   .missed
                    case .noData, nil: .noData
                    }
                }
            )

            let today = rows.first { calendar.isDateInToday($0.date) }

            snapshot = TodaySnapshot(
                date: .now,
                cells: cells,
                streak: currentStreak(statuses: ordered),
                steps: today?.steps,
                stepsProgress: today?.steps.map { Double($0) / Double(targets.steps) },
                sleepMinutes: today?.sleepMinutes,
                sleepProgress: today?.sleepMinutes.map { Double($0) / Double(targets.sleepMinutes) },
                weightKg: today?.weightKg,
                recoveryPct: today?.whoopRecoveryPct
            )
        } catch {
            // A read failure leaves the previous snapshot in place rather than
            // blanking the screen. Nothing here is recoverable by the user.
            assertionFailure("Today load failed: \(error)")
        }
    }
}
