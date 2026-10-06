import Foundation

/// The wording around finding events on the calendar screen, as tested
/// values: the field's placeholder, the eyebrow over the results, the
/// sentence that names the scope, the overflow line, each result's
/// day-and-time label, and the line shown when asking is not possible.
public enum ScheduleFindText {
    public static let placeholder = "Find or ask about your schedule"
    public static let needsModel = "Asking needs Apple Intelligence on this device."
    static let askFurther = "Ask for anything further out."

    /// `Found 3`, or `Nothing found`. Drawn through `editorialEyebrow()`,
    /// which uppercases it.
    public static func eyebrow(found count: Int) -> String {
        count == 0 ? "Nothing found" : "Found \(count)"
    }

    /// `In October and November. Ask for anything further out.`: the months
    /// the find covers, so a miss reads as "not here", not "not anywhere".
    public static func scope(months: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let names = months.map { $0.formatted(style.month(.wide)) }
        guard let last = names.last else { return askFurther }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return "In \(list). \(askFurther)"
    }

    /// `4 more`, under the eighth row.
    public static func more(_ hidden: Int) -> String { "\(hidden) more" }

    /// `Tue 13 · 10:00`, or `Tue 13 · All day`: the day a person scans for,
    /// then the time the way the device shows it. Weekday and day are
    /// formatted separately because one format puts the day first in some
    /// locales. An all-day event keeps its day: birthdays and trips are
    /// exactly what people search for.
    public static func rowLabel(start: Date, isAllDay: Bool, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let weekday = start.formatted(style.weekday(.abbreviated))
        let day = start.formatted(style.day())
        let time = isAllDay ? "All day" : start.formatted(style.hour().minute())
        return "\(weekday) \(day) · \(time)"
    }
}
