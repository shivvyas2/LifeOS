import Foundation
import SwiftData

/// Windowed reads and sync writes over the calendar cache. Never talks to a
/// provider; `CalendarSync` owns that side and feeds fetches through `apply`.
@MainActor
public struct CalendarStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Events overlapping the half-open interval `[from, to)`, sorted by start.
    /// Overlap is strict, so an event ending exactly at `from` is excluded.
    public func events(from: Date, to: Date) throws -> [CalendarEventSnapshot] {
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate < to && $0.endDate > from },
            sortBy: [SortDescriptor(\.startDate), SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor).map { $0.snapshot() }
    }

    public func snapshot(id: UUID) throws -> CalendarEventSnapshot? {
        try row(id: id)?.snapshot()
    }

    /// Reconciles one provider fetch into the cache.
    ///
    /// Matches on the natural key `(source, sourceID)`: an existing row is
    /// updated in place and keeps its local id, a new one adopts the
    /// snapshot's. Rows overlapping `window` whose key is absent from
    /// `fetched` are deleted, so deletions made in another app propagate.
    /// Rows outside the window are never touched.
    public func apply(_ fetched: [CalendarEventSnapshot], window: DateInterval, syncedAt: Date = .now) throws {
        let start = window.start
        let end = window.end
        let cached = try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.startDate < end && $0.endDate > start }
        ))
        var cachedByKey = Dictionary(
            cached.map { (Key(sourceRaw: $0.sourceRaw, sourceID: $0.sourceID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for snapshot in fetched {
            let key = Key(sourceRaw: snapshot.source.rawValue, sourceID: snapshot.sourceID)
            if let row = cachedByKey.removeValue(forKey: key) {
                updateRow(row, from: snapshot, syncedAt: syncedAt)
            } else if let row = try rowByKey(sourceRaw: snapshot.source.rawValue, sourceID: snapshot.sourceID) {
                updateRow(row, from: snapshot, syncedAt: syncedAt)
            } else {
                context.insert(CalendarEvent(from: snapshot, syncedAt: syncedAt))
            }
        }

        // Whatever remains was in the window but not in the fetch: deleted upstream.
        cachedByKey.values.forEach(context.delete)
        try context.save()
    }

    private func updateRow(_ row: CalendarEvent, from snapshot: CalendarEventSnapshot, syncedAt: Date) {
        row.calendarTitle = snapshot.calendarTitle
        row.title = snapshot.title
        row.startDate = snapshot.startDate
        row.endDate = snapshot.endDate
        row.isAllDay = snapshot.isAllDay
        row.isRecurring = snapshot.isRecurring
        row.location = snapshot.location
        row.notes = snapshot.notes
        row.lastSyncedAt = syncedAt
    }

    private func rowByKey(sourceRaw: String, sourceID: String) throws -> CalendarEvent? {
        try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw && $0.sourceID == sourceID }
        )).first
    }

    private func row(id: UUID) throws -> CalendarEvent? {
        try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private struct Key: Hashable {
        let sourceRaw: String
        let sourceID: String
    }
}
