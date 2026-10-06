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
    /// The events with these ids, in one fetch.
    ///
    /// For rebuilding the cards under an assistant reply, where the ids were
    /// stored and the events were not. Anything since deleted is simply absent
    /// from the result, which is what lets a stale card disappear rather than
    /// linger.
    public func events(withIDs ids: Set<UUID>) throws -> [CalendarEventSnapshot] {
        guard !ids.isEmpty else { return [] }
        return try context
            .fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { ids.contains($0.id) }))
            .map { $0.snapshot() }
    }

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

    /// The cached row for a provider's event, by its natural key. The id a
    /// source hands back from a write is provisional; this is how a caller
    /// finds the id the rest of the app can look the event up by.
    public func snapshot(source: CalendarEventSource, sourceID: String) throws -> CalendarEventSnapshot? {
        try rowByKey(sourceRaw: source.rawValue, sourceID: sourceID)?.snapshot()
    }

    /// Reconciles one provider fetch into the cache.
    ///
    /// Matches on the natural key `(source, sourceID)`: an existing row is
    /// updated in place and keeps its local id, a new one adopts the
    /// snapshot's. The fetch is only authoritative for the sources in
    /// `authoritative` (every source by default): rows overlapping `window`
    /// whose key is absent from `fetched` are deleted only when their source
    /// is in that set, so deletions made in another app propagate. A source
    /// that was not actually fetched this pass (it threw, or was skipped)
    /// is left untouched rather than treated as having reported zero
    /// events. Rows outside the window are never touched.
    public func apply(
        _ fetched: [CalendarEventSnapshot],
        window: DateInterval,
        authoritative: Set<CalendarEventSource> = Set(CalendarEventSource.allCases),
        syncedAt: Date = .now
    ) throws {
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

        // Whatever remains was in the window but not in the fetch: deleted
        // upstream, but only for a source we actually fetched this pass.
        cachedByKey.values
            .filter { authoritative.contains($0.source) }
            .forEach(context.delete)
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

extension CalendarStore {
    /// Open intervals of at least `durationMinutes` inside `[from, to)`.
    /// All-day events do not block time: "Anniversary" is context, not a
    /// meeting, and treating it as busy would zero out the whole day.
    public func freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval] {
        let busy = try events(from: from, to: to)
            .filter { !$0.isAllDay }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        return Self.freeSlots(
            in: DateInterval(start: from, end: to),
            busy: busy,
            durationMinutes: durationMinutes
        )
    }

    /// Pure core: merge busy intervals, subtract from the window, drop gaps
    /// shorter than the requested duration.
    nonisolated static func freeSlots(in window: DateInterval, busy: [DateInterval], durationMinutes: Int) -> [DateInterval] {
        let minimum = TimeInterval(durationMinutes * 60)
        var merged: [DateInterval] = []
        for interval in busy.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        var slots: [DateInterval] = []
        var cursor = window.start
        for interval in merged {
            let gapEnd = min(interval.start, window.end)
            if gapEnd.timeIntervalSince(cursor) >= minimum {
                slots.append(DateInterval(start: cursor, end: gapEnd))
            }
            cursor = max(cursor, interval.end)
            if cursor >= window.end { return slots }
        }
        if window.end.timeIntervalSince(cursor) >= minimum {
            slots.append(DateInterval(start: cursor, end: window.end))
        }
        return slots
    }
}
