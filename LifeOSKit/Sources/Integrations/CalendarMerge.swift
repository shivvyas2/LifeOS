import Foundation
import Persistence

/// DayGuide's dedup rule, kept verbatim: two events collide when the
/// lowercased title and the start date are both equal. EventKit wins because
/// that copy is writable offline and is what the OS shows elsewhere. When the
/// user's Google account is also added under iOS Settings this rule is the
/// only thing preventing every event from appearing twice.
public enum CalendarMerge {
    public static func merge(
        eventKit: [CalendarEventSnapshot],
        google: [CalendarEventSnapshot]
    ) -> [CalendarEventSnapshot] {
        struct Key: Hashable {
            let title: String
            let start: Date
        }
        let taken = Set(eventKit.map { Key(title: $0.title.lowercased(), start: $0.startDate) })
        let unique = google.filter { !taken.contains(Key(title: $0.title.lowercased(), start: $0.startDate)) }
        return eventKit + unique
    }
}
