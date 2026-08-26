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
    /// Fields left untouched by `apply` are preserved: this is a merge, not a
    /// replace, so HealthKit and Whoop can both write the same row safely.
    @discardableResult
    public func upsert(date: Date, apply: (DailyMetrics) -> Void) throws -> DailyMetrics {
        let row = try row(for: date)
        apply(row)
        row.updatedAt = .now
        try context.save()
        return row
    }

    /// Many days, one `save()`. Seeding and sync loops go through this, because a save
    /// per row turns 60 days into 60 disk transactions on the main actor.
    public func upsertBatch(dates: [Date], apply: (Date, DailyMetrics) -> Void) throws {
        for date in dates {
            let row = try row(for: date)
            apply(date, row)
            row.updatedAt = .now
        }
        try context.save()
    }

    /// The existing row for `date`'s day, or a freshly inserted one.
    /// Unsaved. Callers decide when to commit.
    private func row(for date: Date) throws -> DailyMetrics {
        let day = calendar.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date == day })

        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let row = DailyMetrics(date: day)
        context.insert(row)
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

    /// Upsert keyed on the provider's record id, so a re-sync corrects a record
    /// rather than adding a second copy of the same night.
    public func upsertSleepRecord(
        externalID: String,
        start: Date,
        end: Date,
        attributedDate: Date,
        apply: (SleepRecord) -> Void
    ) throws {
        let existing = try context.fetch(
            FetchDescriptor<SleepRecord>(predicate: #Predicate { $0.externalID == externalID })
        ).first

        let record = existing ?? SleepRecord(
            externalID: externalID, start: start, end: end, attributedDate: attributedDate
        )
        if existing == nil { context.insert(record) }
        record.start = start
        record.end = end
        record.attributedDate = attributedDate
        apply(record)
        try context.save()
    }

    /// Upsert keyed on the provider's record id, so a re-sync corrects a
    /// workout rather than adding a second copy of the same session.
    /// A day's sessions, oldest first, which is the order they happened and the
    /// order a list of them is read.
    public func workouts(on date: Date) throws -> [WorkoutRecord] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try context.fetch(
            FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate { $0.start >= start && $0.start < end },
                sortBy: [SortDescriptor(\.start)]
            )
        )
    }

    /// Workouts starting within the window, oldest first. `to` is inclusive of
    /// the whole day, matching `sleepRecords(from:to:)`.
    public func workouts(from: Date, to: Date) throws -> [WorkoutRecord] {
        let start = calendar.startOfDay(for: from)
        guard let end = calendar.date(byAdding: .day, value: 1,
                                      to: calendar.startOfDay(for: to)) else { return [] }
        return try context.fetch(
            FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate { $0.start >= start && $0.start < end },
                sortBy: [SortDescriptor(\.start)]
            )
        )
    }

    /// Sleep records attributed to days in the window, oldest first.
    ///
    /// `includingNaps` defaults to true because the records are stored for their
    /// own sake. A night-by-night view passes false: a nap is real, but it is
    /// not a night, and stacking it beside one misreads the week.
    public func sleepRecords(
        from: Date, to: Date, includingNaps: Bool = true
    ) throws -> [SleepRecord] {
        let start = calendar.startOfDay(for: from)
        guard let end = calendar.date(byAdding: .day, value: 1,
                                      to: calendar.startOfDay(for: to)) else { return [] }
        let records = try context.fetch(
            FetchDescriptor<SleepRecord>(
                predicate: #Predicate { $0.attributedDate >= start && $0.attributedDate < end },
                sortBy: [SortDescriptor(\.attributedDate)]
            )
        )
        return includingNaps ? records : records.filter { $0.isNap != true }
    }

    public func upsertWorkoutRecord(
        externalID: String,
        start: Date,
        durationMinutes: Int,
        activityName: String,
        apply: (WorkoutRecord) -> Void
    ) throws {
        let existing = try context.fetch(
            FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.externalID == externalID })
        ).first

        let record = existing ?? WorkoutRecord(
            externalID: externalID, start: start,
            durationMinutes: durationMinutes, activityName: activityName
        )
        if existing == nil { context.insert(record) }
        record.start = start
        record.durationMinutes = durationMinutes
        record.activityName = activityName
        apply(record)
        try context.save()
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
