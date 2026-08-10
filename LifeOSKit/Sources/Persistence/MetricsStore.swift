import Foundation
import SwiftData

/// The only way anything writes to `DailyMetrics`. Enforces the
/// one-row-per-calendar-day invariant so callers cannot get it wrong.
@MainActor
public struct MetricsStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Fetches or creates the row for `date`'s day and applies `apply` to it.
    /// Fields left untouched by `apply` are preserved — this is a merge, not a
    /// replace, so HealthKit and Whoop can both write the same row safely.
    @discardableResult
    public func upsert(date: Date, apply: (DailyMetrics) -> Void) throws -> DailyMetrics {
        let day = calendar.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date == day })

        let row: DailyMetrics
        if let existing = try context.fetch(descriptor).first {
            row = existing
        } else {
            row = DailyMetrics(date: day)
            context.insert(row)
        }

        apply(row)
        row.updatedAt = .now
        try context.save()
        return row
    }

    /// Most-recent-first, matching the order `currentStreak` expects.
    public func metrics(from start: Date, to end: Date) throws -> [DailyMetrics] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.startOfDay(for: end)
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date >= lower && $0.date <= upper },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// There is exactly one goals row. Created with spec defaults on first access.
    public func goals() throws -> UserGoals {
        if let existing = try context.fetch(FetchDescriptor<UserGoals>()).first {
            return existing
        }
        let goals = UserGoals()
        context.insert(goals)
        try context.save()
        return goals
    }
}
