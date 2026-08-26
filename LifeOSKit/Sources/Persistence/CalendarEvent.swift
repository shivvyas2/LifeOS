import Foundation
import SwiftData

public enum CalendarEventSource: String, Codable, Sendable, CaseIterable {
    case eventKit, google
}

/// Detached value form, safe to hand to a view or an assistant tool.
/// `Sendable` is the point: a tool result crosses into an engine, and a
/// `CalendarEvent` cannot make that trip because it is not Sendable.
public struct CalendarEventSnapshot: Equatable, Identifiable, Sendable {
    /// Local identity. Provisional when the snapshot comes from a provider
    /// fetch; `CalendarStore.apply` preserves the id of an existing row and
    /// only adopts this one for genuinely new events.
    public let id: UUID
    public let source: CalendarEventSource
    /// EKEvent.eventIdentifier, or the Google event id. Unique within a source.
    public let sourceID: String
    public let calendarTitle: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    /// One occurrence of a recurring series. Gated writes refuse these.
    public let isRecurring: Bool
    public let location: String?
    public let notes: String?

    public init(
        id: UUID, source: CalendarEventSource, sourceID: String,
        calendarTitle: String, title: String,
        startDate: Date, endDate: Date,
        isAllDay: Bool, isRecurring: Bool,
        location: String?, notes: String?
    ) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.calendarTitle = calendarTitle
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isRecurring = isRecurring
        self.location = location
        self.notes = notes
    }
}

/// What a caller supplies to create or edit an event. No id, no source:
/// routing decides those.
public struct CalendarEventDraft: Equatable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?

    public init(
        title: String, startDate: Date, endDate: Date,
        isAllDay: Bool = false, location: String? = nil, notes: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

@Model
public final class CalendarEvent {
    public var id: UUID
    /// Stored raw so the enum can gain cases without a migration.
    public var sourceRaw: String
    public var sourceID: String
    public var calendarTitle: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var isRecurring: Bool
    public var location: String?
    public var notes: String?
    public var lastSyncedAt: Date

    public init(from snapshot: CalendarEventSnapshot, syncedAt: Date = .now) {
        self.id = snapshot.id
        self.sourceRaw = snapshot.source.rawValue
        self.sourceID = snapshot.sourceID
        self.calendarTitle = snapshot.calendarTitle
        self.title = snapshot.title
        self.startDate = snapshot.startDate
        self.endDate = snapshot.endDate
        self.isAllDay = snapshot.isAllDay
        self.isRecurring = snapshot.isRecurring
        self.location = snapshot.location
        self.notes = snapshot.notes
        self.lastSyncedAt = syncedAt
    }

    public var source: CalendarEventSource {
        get { CalendarEventSource(rawValue: sourceRaw) ?? .eventKit }
        set { sourceRaw = newValue.rawValue }
    }

    public func snapshot() -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, source: source, sourceID: sourceID,
            calendarTitle: calendarTitle, title: title,
            startDate: startDate, endDate: endDate,
            isAllDay: isAllDay, isRecurring: isRecurring,
            location: location, notes: notes
        )
    }
}
