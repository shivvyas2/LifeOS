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

    /// The window the calendar screen loads for a shown month: the month, the
    /// next, and a week either side, so a week that starts in the previous
    /// month is answerable without a second fetch. A day outside it is one
    /// the screen must move to, not merely select, or its week shows nothing.
    public static func window(forMonth month: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let from = calendar.date(byAdding: .day, value: -7, to: startOfMonth),
              let endOfMonth = calendar.date(byAdding: .month, value: 2, to: startOfMonth),
              let to = calendar.date(byAdding: .day, value: 7, to: endOfMonth)
        else { return nil }
        return DateInterval(start: from, end: to)
    }
}
