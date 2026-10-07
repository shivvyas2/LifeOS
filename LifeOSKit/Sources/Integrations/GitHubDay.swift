import Foundation

/// A local calendar day, as GitHub's search wants it.
public enum GitHubDay {
    public static func bounds(for day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// `author:<login> author-date:<start>..<end>`, inclusive at both ends,
    /// each written with its own offset so a daylight-saving day is right.
    /// Author date, so a commit rebased today stays on the day it was written.
    public static func commitQuery(login: String, day: Date, calendar: Calendar) -> String {
        let (start, end) = bounds(for: day, calendar: calendar)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        let last = end.addingTimeInterval(-1)
        func stamp(_ date: Date) -> String {
            formatter.timeZone = TimeZone(secondsFromGMT: calendar.timeZone.secondsFromGMT(for: date))
            return formatter.string(from: date)
        }
        return "author:\(login) author-date:\(stamp(start))..\(stamp(last))"
    }
}
