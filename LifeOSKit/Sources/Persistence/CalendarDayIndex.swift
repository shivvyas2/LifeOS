import Foundation

/// Indexes overlapping events on every visible day, with an exclusive end date.
public enum CalendarDayIndex {
    public static func group(_ events: [CalendarEventSnapshot], from: Date, to: Date,
                             calendar: Calendar = .current) -> [Date: [CalendarEventSnapshot]] {
        guard from < to else { return [:] }
        var result: [Date: [CalendarEventSnapshot]] = [:]
        for event in events where event.startDate < to && event.endDate > from {
            var day = calendar.startOfDay(for: max(event.startDate, from))
            let end = min(event.endDate, to)
            while day < end {
                result[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
            }
        }
        return result
    }
}
