import Foundation
import SwiftData
import DesignSystem
import Persistence

@MainActor @Observable
final class TodayViewModel {
    private(set) var snapshot = TodaySnapshot()
    /// The day the sheet is showing, or nil when it is closed.
    private(set) var detail: DayDetailSnapshot?

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

            // Keeps an open sheet current on every reload, including the
            // `didSave`-driven one in `RootView`. Without this, an external
            // write (a Whoop sync, a tick from `toggleHabit`) updates the grid
            // behind the sheet but not the sheet itself until the next tick or
            // a dismiss-and-reopen.
            if let detail {
                select(detail.date)
            }
        } catch {
            // A read failure leaves the previous snapshot in place rather than
            // blanking the screen. Nothing here is recoverable by the user.
            assertionFailure("Today load failed: \(error)")
        }
    }

    /// Builds the day sheet's contents from both stores.
    ///
    /// A day with no metrics row is not an early return: its habits are still
    /// worth showing, and the metric rows render as blanks.
    func select(_ date: Date) {
        guard let context else { return }
        let metrics = MetricsStore(context: context, calendar: calendar)
        let plan = PlanStore(context: context, calendar: calendar)

        do {
            let day = calendar.startOfDay(for: date)
            let targets = try metrics.goals().targets
            let row = try metrics.metrics(from: day, to: day).first
            let ticked = try plan.tickedHabitIDs(on: day)

            detail = DayDetailSnapshot(
                date: day,
                isToday: calendar.isDateInToday(day),
                steps: row?.steps,
                stepsTarget: targets.steps,
                sleepMinutes: row?.sleepMinutes,
                sleepTargetMinutes: targets.sleepMinutes,
                weightKg: row?.weightKg,
                recoveryPct: row?.whoopRecoveryPct,
                habits: try plan.entries(kind: .habit).map { entry in
                    HabitRow(id: entry.id, title: entry.title, isDone: ticked.contains(entry.id))
                }
            )
        } catch {
            assertionFailure("Day detail load failed: \(error)")
        }
    }

    func clearSelection() {
        detail = nil
    }

    /// Only today can be ticked. Past days are history, and the sheet renders
    /// them without controls, so this guard is the second lock rather than the
    /// only one.
    func toggleHabit(id: UUID) {
        guard let context, let detail, detail.isToday else { return }

        do {
            let entry = try context.fetch(
                FetchDescriptor<PlanEntry>(predicate: #Predicate { $0.id == id })
            ).first
            guard let entry else { return }

            try PlanStore(context: context, calendar: calendar)
                .toggleTick(for: entry, on: detail.date)

            // No refresh here: `toggleTick` saves, `RootView` reloads every
            // view model on `ModelContext.didSave`, and `load()` above
            // re-derives `detail` whenever it is open. That is the one
            // refresh path; calling `load()`/`select()` again here would
            // just repeat the ~400-day grid pass a second time per tap.
        } catch {
            assertionFailure("Habit toggle failed: \(error)")
        }
    }
}
