import EventKit
import Foundation
import Persistence

/// EventKit behind `CalendarSource`. An actor because `EKEventStore` is not
/// Sendable and wants all access on one executor.
public actor EventKitSource: CalendarSource {
    public nonisolated let source: CalendarEventSource = .eventKit
    private let store = EKEventStore()

    private let defaults: UserDefaults
    private let ownerID: String?

    public init(defaults: UserDefaults = .currentAccount) {
        self.defaults = defaults
        self.ownerID = UserDefaults.standard.string(forKey: "accounts.current")
    }

    private var isCurrentAccount: Bool {
        ownerID != nil && ownerID == UserDefaults.standard.string(forKey: "accounts.current")
    }

    public var isAuthorized: Bool {
        isCurrentAccount && AccountDeviceAccess.allowsCalendar(defaults: defaults,
            systemAuthorized: EKEventStore.authorizationStatus(for: .event) == .fullAccess)
    }

    /// Presents the system prompt. Callers decide when; per the spec that is
    /// the agenda card's empty state, never launch.
    public func requestAccess() async throws -> Bool {
        guard isCurrentAccount else { return false }
        let granted = try await store.requestFullAccessToEvents()
        guard isCurrentAccount else { return false }
        defaults.set(granted, forKey: AccountDeviceAccess.calendarKey)
        return granted
    }

    public func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot] {
        guard isAuthorized else { throw CalendarSyncError.noWritableSource }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).compactMap { snapshot(of: $0) }
    }

    public func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        guard isAuthorized else { throw CalendarSyncError.noWritableSource }
        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = snapshot(of: event) else { throw CalendarSyncError.unknownEvent }
        return saved
    }

    public func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        guard isAuthorized else { throw CalendarSyncError.noWritableSource }
        let event = try existing(sourceID)
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = snapshot(of: event) else { throw CalendarSyncError.unknownEvent }
        return saved
    }

    public func delete(sourceID: String) async throws {
        guard isAuthorized else { throw CalendarSyncError.noWritableSource }
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
