import Foundation
import Persistence

/// One habit as the day sheet renders it.
struct HabitRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isDone: Bool
}

/// Everything the day sheet renders, as plain values.
///
/// Same discipline as `TodaySnapshot`: the sheet never sees a `DailyMetrics` or
/// a `PlanEntry`, so rendering cannot fault a SwiftData object mid-layout.
///
/// `Identifiable` on the date is required by `.sheet(item:)`, which is what
/// presents this sheet in `RootView`.
struct DayDetailSnapshot: Identifiable, Equatable {
    var id: Date { date }

    /// Always `Calendar.startOfDay`.
    let date: Date
    let isToday: Bool

    let steps: Int?
    let stepsTarget: Int
    let sleepMinutes: Int?
    let sleepTargetMinutes: Int
    let weightKg: Double?
    let recoveryPct: Double?

    /// Every habit that currently exists, done or not. Deliberately not
    /// filtered by creation date — see the spec's "Decision that shapes the
    /// sheet". The consequence is that an old day can list a habit that did not
    /// exist then, which is why the sheet's header is a count and never a grade.
    let habits: [HabitRow]

    /// That day's schedule. Empty when access is missing or nothing is on.
    var events: [CalendarEventSnapshot] = []
}
