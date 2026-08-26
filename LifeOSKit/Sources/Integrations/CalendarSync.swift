import Foundation
import Persistence

public enum CalendarSyncError: Error, Equatable {
    /// The id does not name a cached event. Ids only ever come from the
    /// store, so this is a caller bug or a stale reference, never user input.
    case unknownEvent
    /// No source is authorized to accept the write.
    case noWritableSource
}

/// Pulls every authorized source, merges, and reconciles the cache; routes
/// writes back to the source owning the event, then re-syncs so the cache
/// reflects what the provider actually stored (providers normalise all-day
/// handling and timezones, so trusting the local draft would drift).
///
/// `@MainActor` rather than the spec's "actor": the store it drives owns a
/// `ModelContext`, and MainActor gives the same serialisation `WhoopSync`
/// already relies on.
@MainActor
public final class CalendarSync {
    private let sources: [any CalendarSource]
    private let store: CalendarStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        sources: [any CalendarSource],
        store: CalendarStore,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.sources = sources
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    /// 30 days back, 90 days forward, matching DayGuide.
    public var window: DateInterval {
        let today = calendar.startOfDay(for: now())
        return DateInterval(
            start: calendar.date(byAdding: .day, value: -30, to: today) ?? today,
            end: calendar.date(byAdding: .day, value: 90, to: today) ?? today
        )
    }

    /// One pass. A source that throws is skipped; partial data beats an
    /// empty screen. Errors are not surfaced here because sync is ambient
    /// (scene activation, post-write), never a user-visible request.
    public func sync() async {
        let window = window
        var bySource: [CalendarEventSource: [CalendarEventSnapshot]] = [:]
        for source in sources {
            guard await source.isAuthorized else { continue }
            do {
                bySource[source.source] = try await source.events(from: window.start, to: window.end)
            } catch {
                continue
            }
        }
        guard !bySource.isEmpty else { return }

        let merged = CalendarMerge.merge(
            eventKit: bySource[.eventKit] ?? [],
            google: bySource[.google] ?? []
        )
        try? store.apply(merged, window: window, syncedAt: now())
    }

    public func create(_ draft: CalendarEventDraft) async throws {
        for source in sources {
            guard await source.isAuthorized else { continue }
            _ = try await source.create(draft)
            await sync()
            return
        }
        throw CalendarSyncError.noWritableSource
    }

    public func update(id: UUID, with draft: CalendarEventDraft) async throws {
        let event = try existing(id: id)
        _ = try await owner(of: event).update(sourceID: event.sourceID, with: draft)
        await sync()
    }

    public func delete(id: UUID) async throws {
        let event = try existing(id: id)
        try await owner(of: event).delete(sourceID: event.sourceID)
        await sync()
    }

    private func existing(id: UUID) throws -> CalendarEventSnapshot {
        guard let event = try? store.snapshot(id: id) else {
            throw CalendarSyncError.unknownEvent
        }
        return event
    }

    private func owner(of event: CalendarEventSnapshot) throws -> any CalendarSource {
        guard let source = sources.first(where: { $0.source == event.source }) else {
            throw CalendarSyncError.noWritableSource
        }
        return source
    }
}
