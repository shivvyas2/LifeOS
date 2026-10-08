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
    public func focusedSeconds(on day: Date, calendar: Calendar = .current) throws -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate {
            $0.startedAt >= start && $0.startedAt < end && $0.mood != "sleep"
        })
        return try context.fetch(descriptor).reduce(0) { $0 + $1.focusedSeconds }
    }
}
