import Foundation
import SwiftData

/// A person's mark on a catalog video: saved for later, scheduled for a day,
/// or both. One row per video id; absent means neither.
@Model
public final class WorkoutBookmark {
    #Unique<WorkoutBookmark>([\.youtubeID])
    public var youtubeID: String
    public var saved: Bool
    /// A calendar day start, never a timestamp.
    public var scheduledFor: Date?
    public var updatedAt: Date

    public init(youtubeID: String, saved: Bool = false, scheduledFor: Date? = nil, updatedAt: Date = .now) {
        self.youtubeID = youtubeID
        self.saved = saved
        self.scheduledFor = scheduledFor
        self.updatedAt = updatedAt
    }
}

public enum BookmarkStore {
    public static func all(context: ModelContext) throws -> [WorkoutBookmark] {
        try context.fetch(FetchDescriptor<WorkoutBookmark>(sortBy: [SortDescriptor(\.youtubeID)]))
    }

    public static func bookmark(for id: String, context: ModelContext) throws -> WorkoutBookmark? {
        try context.fetch(FetchDescriptor<WorkoutBookmark>(
            predicate: #Predicate { $0.youtubeID == id }
        )).first
    }

    /// Toggles saved; deletes the row when it ends up neither saved nor scheduled.
    @discardableResult
    public static func toggleSaved(_ id: String, context: ModelContext) throws -> Bool {
        if let row = try bookmark(for: id, context: context) {
            row.saved.toggle()
            row.updatedAt = .now
            // Read before the delete: a deleted model is not a thing to ask
            // questions of, even one it answered correctly a line earlier.
            let saved = row.saved
            if !(saved || row.scheduledFor != nil) {
                context.delete(row)
            }
            try context.save()
            return saved
        } else {
            let row = WorkoutBookmark(youtubeID: id, saved: true)
            context.insert(row)
            try context.save()
            return true
        }
    }

    /// Sets or clears the day (normalised to startOfDay with the calendar); deletes an empty row.
    public static func schedule(_ id: String, on day: Date?, context: ModelContext, calendar: Calendar = .current) throws {
        let normalised = day.map { calendar.startOfDay(for: $0) }
        if let row = try bookmark(for: id, context: context) {
            row.scheduledFor = normalised
            row.updatedAt = .now
            let stillWanted = row.saved || row.scheduledFor != nil
            if !stillWanted {
                context.delete(row)
            }
        } else if let normalised {
            context.insert(WorkoutBookmark(youtubeID: id, saved: false, scheduledFor: normalised))
        }
        try context.save()
    }

    public static func scheduled(on day: Date, context: ModelContext, calendar: Calendar = .current) throws -> [WorkoutBookmark] {
        let dayStart = calendar.startOfDay(for: day)
        return try context.fetch(FetchDescriptor<WorkoutBookmark>(
            predicate: #Predicate { $0.scheduledFor == dayStart },
            sortBy: [SortDescriptor(\.youtubeID)]
        ))
    }
}
