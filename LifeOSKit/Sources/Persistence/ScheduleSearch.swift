import Foundation

/// Finds events by the words a person would type: part of a title, a
/// place, or the name of the calendar. Local and instant; nothing here
/// fetches or asks a model.
public enum ScheduleSearch {
    /// Matches are case- and diacritic-insensitive (`localizedStandardContains`),
    /// sorted by start then title, and de-duplicated by id, because the
    /// day index hands a multi-day event back once per day it covers.
    public static func matches(_ query: String, in events: [CalendarEventSnapshot]) -> [CalendarEventSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var seen: Set<UUID> = []
        return events
            .filter { event in
                event.title.localizedStandardContains(needle)
                    || (event.location?.localizedStandardContains(needle) ?? false)
                    || event.calendarTitle.localizedStandardContains(needle)
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }
            .filter { seen.insert($0.id).inserted }
    }
}
