import Foundation

/// Today's masthead: which day, a greeting for today or the weekday for
/// any other day, and the streak. A value so the wording is tested.
public struct TodayHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String

    public init(eyebrow: String, title: String, detail: String) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    public static func make(
        date: Date, now: Date = .now, streak: Int,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> TodayHeadline {
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let style = Date.FormatStyle(locale: locale, calendar: calendar)
        let eyebrow = isToday
            ? "Today · \(date.formatted(style.weekday(.wide).month(.abbreviated).day()))"
            : date.formatted(style.month(.abbreviated).day())
        let title: String
        if isToday {
            let hour = calendar.component(.hour, from: now)
            title = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        } else {
            title = date.formatted(style.weekday(.wide))
        }
        let detail = streak > 0 ? "\(streak)-day streak" : "Start a streak today"
        return TodayHeadline(eyebrow: eyebrow, title: title, detail: detail)
    }
}
