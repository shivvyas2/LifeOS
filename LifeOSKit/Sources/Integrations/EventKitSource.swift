import EventKit
import Foundation
import Persistence

/// EventKit behind `CalendarSource`. An actor because `EKEventStore` is not
/// Sendable and wants all access on one executor.
public actor EventKitSource: CalendarSource {
    public nonisolated let source: CalendarEventSource = .eventKit
    private let store = EKEventStore()

    public init() {}

    public var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Presents the system prompt. Callers decide when; per the spec that is
    /// the agenda card's empty state, never launch.
    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).compactMap { snapshot(of: $0) }
    }

    public func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = snapshot(of: event) else { throw CalendarSyncError.unknownEvent }
        return saved
    }

    public func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        let event = try existing(sourceID)
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = snapshot(of: event) else { throw CalendarSyncError.unknownEvent }
        return saved
    }

    public func delete(sourceID: String) async throws {
        try store.remove(try existing(sourceID), span: .thisEvent, commit: true)
    }

    private func existing(_ sourceID: String) throws -> EKEvent {
        guard let event = store.event(withIdentifier: sourceID) else {
            throw CalendarSyncError.unknownEvent
        }
        return event
    }

    private func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
    }

    /// An EKEvent with no identifier (possible for unsaved or broken rows)
    /// has no natural key and is dropped rather than cached unmatchable.
    private func snapshot(of event: EKEvent) -> CalendarEventSnapshot? {
        guard let identifier = event.eventIdentifier else { return nil }
        let isRecurring = event.hasRecurrenceRules || event.isDetached
        return CalendarEventSnapshot(
            id: UUID(),
            source: .eventKit,
            sourceID: Self.sourceID(identifier: identifier, startDate: event.startDate, isRecurring: isRecurring),
            calendarTitle: event.calendar?.title ?? "",
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            isRecurring: isRecurring,
            location: event.location,
            notes: event.notes
        )
    }

    /// Occurrences of a recurring series share one EKEvent identifier, so a
    /// recurring row's natural key is qualified with its occurrence start.
    /// A qualified id never resolves through `event(withIdentifier:)`, which
    /// makes writes against occurrences fail with `unknownEvent` instead of
    /// silently editing the wrong occurrence; the tool layer refuses recurring
    /// writes with a real explanation before that can happen.
    static func sourceID(identifier: String, startDate: Date, isRecurring: Bool) -> String {
        isRecurring ? "\(identifier)#\(Int(startDate.timeIntervalSince1970))" : identifier
    }
}
