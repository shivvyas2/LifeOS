import Foundation

/// Which face the calendar screen shows: two months on grids, or the seven
/// days around the selected day as bands.
public enum CalendarMode: Hashable, Sendable {
    case monthly, weekly
}

/// The calendar screen's masthead by mode. The eyebrow names the mode and
/// the period, the title is always `Calendar`, and Weekly adds the week's
/// range as the detail line. A value so the wording is tested.
public struct CalendarHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String
    public let detail: String?

    public init(eyebrow: String, title: String, detail: String?) {
        self.eyebrow = eyebrow; self.title = title; self.detail = detail
    }

    /// `month` is any day in the month Monthly shows; `selection` is the
    /// day Weekly is built around. Each mode reads only its own, so the
    /// Monthly year never follows today and the Weekly month never follows
    /// the grid.
    public static func make(
        mode: CalendarMode, month: Date, selection: Date,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> CalendarHeadline {
        // The calendar's own zone, not the device's: a week start is that
        // calendar's midnight, and formatting it in another zone moves it a day.
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch mode {
        case .monthly:
            return CalendarHeadline(
                eyebrow: "Monthly · \(month.formatted(style.year()))",
                title: "Calendar",
                detail: nil
            )
        case .weekly:
            let days = WeekSpan.days(containing: selection, calendar: calendar)
            let dayStyle = style.month(.abbreviated).day()
            let range: String? = if let first = days.first, let last = days.last {
                "\(first.formatted(dayStyle)) to \(last.formatted(dayStyle))"
            } else {
                nil
            }
            return CalendarHeadline(
                eyebrow: "Weekly · \(selection.formatted(style.month(.wide)))",
                title: "Calendar",
                detail: range
            )
        }
    }
}
