import Foundation
import SwiftData

/// Reads and writes plan entries and their habit history.
@MainActor
public struct PlanStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Entries of one kind, ordered for display.
    public func entries(kind: PlanKind) throws -> [PlanEntry] {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<PlanEntry>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    public func add(
        kind: PlanKind,
        title: String,
        detail: String? = nil,
        status: PlanStatus = .todo,
        dueDate: Date? = nil,
        progressValue: Double? = nil,
        progressTarget: Double? = nil
    ) throws -> PlanEntry {
        let existing = try entries(kind: kind)
        let entry = PlanEntry(
            kind: kind, title: title, detail: detail, status: status,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1,
            dueDate: dueDate, progressValue: progressValue, progressTarget: progressTarget
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    public func delete(_ entry: PlanEntry) throws {
        // Ticks are keyed by id rather than a relationship, so they are cleaned
        // up explicitly — an orphaned tick would resurrect a deleted habit's
        // streak if the id were ever reused.
        let id = entry.id
        let ticks = try context.fetch(
            FetchDescriptor<HabitTick>(predicate: #Predicate { $0.entryID == id })
        )
        ticks.forEach(context.delete)
        context.delete(entry)
        try context.save()
    }

    public func setStatus(_ status: PlanStatus, on entry: PlanEntry) throws {
        entry.status = status
        entry.updatedAt = .now
        try context.save()
    }

    // MARK: - Habits

    /// Completion flags for the last `days` days, oldest first.
    public func recentTicks(for entry: PlanEntry, days: Int = 14, endingOn end: Date = .now) throws -> [Bool] {
        guard days > 0 else { return [] }
        let id = entry.id
        let last = calendar.startOfDay(for: end)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: last) else { return [] }

        let ticked = try context.fetch(
            FetchDescriptor<HabitTick>(
                predicate: #Predicate { $0.entryID == id && $0.date >= first && $0.date <= last }
            )
        )
        let completed = Set(ticked.map(\.date))

        return (0..<days).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return false }
            return completed.contains(day)
        }
    }

    /// Every habit ticked on `date`, in one fetch. `recentTicks` answers the
    /// same question per entry, so assembling a whole day through it would cost
    /// one query per habit.
    public func tickedHabitIDs(on date: Date) throws -> Set<UUID> {
        let day = calendar.startOfDay(for: date)
        let ticks = try context.fetch(
            FetchDescriptor<HabitTick>(predicate: #Predicate { $0.date == day })
        )
        return Set(ticks.map(\.entryID))
    }

    /// Consecutive completed days ending at `end`. An unticked day today does
    /// not break the streak — the day is not over yet.
    public func streak(for entry: PlanEntry, endingOn end: Date = .now) throws -> Int {
        let ticks = try recentTicks(for: entry, days: 365, endingOn: end)
        var count = 0
        for (index, done) in ticks.reversed().enumerated() {
            if done { count += 1 }
            else if index == 0 { continue }   // today still open
            else { break }
        }
        return count
    }

    /// Marks or unmarks a habit for a day. Returns the new state.
    @discardableResult
    public func toggleTick(for entry: PlanEntry, on date: Date = .now) throws -> Bool {
        let id = entry.id
        let day = calendar.startOfDay(for: date)
        let existing = try context.fetch(
            FetchDescriptor<HabitTick>(predicate: #Predicate { $0.entryID == id && $0.date == day })
        )

        if let tick = existing.first {
            context.delete(tick)
            try context.save()
            return false
        }
        context.insert(HabitTick(entryID: id, date: day))
        try context.save()
        return true
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
