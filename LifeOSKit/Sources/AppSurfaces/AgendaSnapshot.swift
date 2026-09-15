import Foundation

/// The calendar projection widgets read: two weeks of plain event values
/// from the start of the current calendar week. Separate from
/// `SurfaceSnapshot` so the Watch payload and the health coalescing rules
/// stay untouched. An empty value with no owner is the tombstone.
public struct AgendaSnapshot: Codable, Equatable, Sendable {
    public static let storageKey = "surface.agenda.v1"
    public static let widgetKind = "AlmanacAgenda"
    public static let eventCap = 80
    public static let windowDays = 14

    public struct Event: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let calendarTitle: String
        public let startDate: Date
        public let endDate: Date
        public let isAllDay: Bool
        public init(id: UUID, title: String, calendarTitle: String,
                    startDate: Date, endDate: Date, isAllDay: Bool) {
            self.id = id
            self.title = title
            self.calendarTitle = calendarTitle
            self.startDate = startDate
            self.endDate = endDate
            self.isAllDay = isAllDay
        }
    }

    public var ownerID: String?
    public var generatedAt: Date
    public var expiresAt: Date
    public var weekStart: Date
    /// Sorted by start then title, capped at `eventCap` keeping the earliest.
    public var events: [Event]

    public init(ownerID: String? = nil, generatedAt: Date = .now, events: [Event] = [],
                calendar: Calendar = .current) {
        self.ownerID = ownerID
        self.generatedAt = generatedAt
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: generatedAt))!
        expiresAt = min(midnight, generatedAt.addingTimeInterval(6 * 3600))
        weekStart = calendar.dateInterval(of: .weekOfYear, for: generatedAt)?.start
            ?? calendar.startOfDay(for: generatedAt)
        self.events = Array(events
            .sorted { ($0.startDate, $0.title) < ($1.startDate, $1.title) }
            .prefix(Self.eventCap))
    }

    /// The query window a publisher should fill from, given a reference time.
    public static func window(around date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    public func isAvailable(at date: Date = .now) -> Bool {
        ownerID != nil && date >= generatedAt.addingTimeInterval(-60) && date < expiresAt
    }

    public func weekDays(calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Events overlapping the day, all-day first, then by start and title.
    public func events(on day: Date, calendar: Calendar = .current) -> [Event] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events
            .filter { $0.startDate < end && $0.endDate > start }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return (a.startDate, a.title) < (b.startDate, b.title)
            }
    }

    /// Events not yet over at `from`, so one in progress stays listed until
    /// it ends. Already sorted by start, which puts a running all-day event
    /// ahead of the timed ones.
    public func upcoming(from: Date, limit: Int = 3) -> [Event] {
        Array(events.filter { $0.endDate > from }.prefix(max(0, limit)))
    }

    public static func read(from defaults: UserDefaults? = UserDefaults(suiteName: SurfaceSnapshot.appGroup)) -> Self? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    public func write(to defaults: UserDefaults? = UserDefaults(suiteName: SurfaceSnapshot.appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }
}

/// A stable slot per calendar name. FNV-1a over UTF-8, not `hashValue`,
/// which is seeded per process and would recolor chips on every launch.
public enum ChipPalette {
    public static let count = 6
    public static func index(for calendarTitle: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in calendarTitle.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(count))
    }
}
