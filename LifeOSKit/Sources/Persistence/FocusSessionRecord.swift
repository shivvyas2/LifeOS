import Foundation
import SwiftData

/// One finished focus session. Every field has a default so stores made
/// before this model existed still open.
@Model public final class FocusSessionRecord {
    public var id: UUID = UUID()
    public var mood: String = "focus"
    public var source: String = "soundscape"
    public var startedAt: Date = Date.now
    public var endedAt: Date?
    public var focusedSeconds: Double = 0
    public var blocksCompleted: Int = 0
    public var projectTaskID: UUID?
    /// When the server confirmed this session. Nil means it still has to go.
    /// Optional, so stores written before sync open unchanged.
    public var syncedAt: Date?

    public init(mood: String, source: String, startedAt: Date, endedAt: Date?, focusedSeconds: Double,
                blocksCompleted: Int, projectTaskID: UUID?) {
        self.mood = mood; self.source = source; self.startedAt = startedAt; self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds; self.blocksCompleted = blocksCompleted; self.projectTaskID = projectTaskID
    }
}

public struct FocusStore {
    let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func record(mood: String, source: String, startedAt: Date, endedAt: Date?, focusedSeconds: Double,
                       blocksCompleted: Int, projectTaskID: UUID?) throws {
        context.insert(FocusSessionRecord(mood: mood, source: source, startedAt: startedAt, endedAt: endedAt,
                                          focusedSeconds: focusedSeconds, blocksCompleted: blocksCompleted,
                                          projectTaskID: projectTaskID))
        try context.save()
    }

    /// Focused time on a day: every mood but Sleep.
    /// Finished sessions the server has not confirmed, oldest first. A
    /// session still running (no end) never goes.
    public func pending(limit: Int = 200) throws -> [FocusSessionRecord] {
        var descriptor = FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.syncedAt == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func markSynced(ids: [UUID], at date: Date = .now) throws {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        for record in try context.fetch(FetchDescriptor<FocusSessionRecord>()) where wanted.contains(record.id) {
            record.syncedAt = date
        }
        try context.save()
    }

    /// Adds sessions recorded elsewhere. A known id is left alone: this
    /// device's copy is the one it wrote, and sessions never change after.
    @discardableResult
    public func merge(remote: [FocusSessionSnapshot], at date: Date = .now) throws -> Int {
        let known = Set(try context.fetch(FetchDescriptor<FocusSessionRecord>()).map(\.id))
        var inserted = 0
        for row in remote where !known.contains(row.id) {
            let record = FocusSessionRecord(mood: row.mood, source: row.source, startedAt: row.startedAt,
                                            endedAt: row.endedAt, focusedSeconds: row.focusedSeconds,
                                            blocksCompleted: row.blocksCompleted, projectTaskID: row.projectTaskID)
            record.id = row.id
            record.syncedAt = date
            context.insert(record)
            inserted += 1
        }
        if inserted > 0 { try context.save() }
        return inserted
    }

    /// Finished sessions, newest first, for a list of recent sessions.
    public func recent(limit: Int = 10) throws -> [FocusSessionSnapshot] {
        var descriptor = FetchDescriptor<FocusSessionRecord>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.snapshot)
    }

    /// Focused time in the calendar week containing `day`. Sleep is rest,
    /// not focus, as on the day total.
    public func focusedSeconds(inWeekOf day: Date, calendar: Calendar = .current) throws -> TimeInterval {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return 0 }
        let start = week.start, end = week.end
        let descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate {
            $0.startedAt >= start && $0.startedAt < end && $0.mood != "sleep"
        })
        return try context.fetch(descriptor).reduce(0) { $0 + $1.focusedSeconds }
    }

    public func focusedSeconds(on day: Date, calendar: Calendar = .current) throws -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate {
            $0.startedAt >= start && $0.startedAt < end && $0.mood != "sleep"
        })
        return try context.fetch(descriptor).reduce(0) { $0 + $1.focusedSeconds }
    }
}

/// A session as plain values: what crosses to and from the server, so the
/// sync layer never holds a model object off its context.
public struct FocusSessionSnapshot: Sendable, Equatable {
    public let id: UUID
    public let mood: String
    public let source: String
    public let startedAt: Date
    public let endedAt: Date?
    public let focusedSeconds: Double
    public let blocksCompleted: Int
    public let projectTaskID: UUID?

    public init(id: UUID, mood: String, source: String, startedAt: Date, endedAt: Date?,
                focusedSeconds: Double, blocksCompleted: Int, projectTaskID: UUID?) {
        self.id = id; self.mood = mood; self.source = source; self.startedAt = startedAt
        self.endedAt = endedAt; self.focusedSeconds = focusedSeconds
        self.blocksCompleted = blocksCompleted; self.projectTaskID = projectTaskID
    }
}

extension FocusSessionRecord {
    public var snapshot: FocusSessionSnapshot {
        FocusSessionSnapshot(id: id, mood: mood, source: source, startedAt: startedAt, endedAt: endedAt,
                             focusedSeconds: focusedSeconds, blocksCompleted: blocksCompleted,
                             projectTaskID: projectTaskID)
    }
}
