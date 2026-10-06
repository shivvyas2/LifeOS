import Foundation

/// Where a day sits relative to today. It decides the eyebrow, which
/// sections the day screen shows, and whether its checklist can change.
public enum DayPlacement: Equatable, Sendable {
    case past(daysAgo: Int)
    case today
    case future(daysAhead: Int)

    public static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> DayPlacement {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days == 0 { return .today }
        return days > 0 ? .future(daysAhead: days) : .past(daysAgo: -days)
    }

    /// A past day is a record; today and the days ahead can be planned.
    public var isEditable: Bool {
        if case .past = self { return false }
        return true
    }
}

/// The day screen's masthead: the eyebrow says where the day sits and the
/// date, the title is the weekday. A value so the wording is tested.
public struct DayHeadline: Equatable, Sendable {
    public let eyebrow: String
    public let title: String

    public init(eyebrow: String, title: String) {
        self.eyebrow = eyebrow; self.title = title
    }

    public static func make(date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> DayHeadline {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        // Day then month, built by hand: one format puts the month first in
        // some locales, and the eyebrow reads as a date either way.
        let dayMonth = "\(date.formatted(style.day())) \(date.formatted(style.month(.wide)))"
        let placement: String? = switch DayPlacement.of(date, now: now, calendar: calendar) {
        case .today: "Today"
        case .past(let n) where n == 1: "Yesterday"
        case .future(let n) where n == 1: "Tomorrow"
        case .past(let n) where n <= 6: "\(n) days ago"
        case .future(let n) where n <= 6: "In \(n) days"
        default: nil
        }
        let eyebrow: String
        if let placement {
            eyebrow = "\(placement) · \(dayMonth)"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            eyebrow = dayMonth
        } else {
            eyebrow = "\(dayMonth) \(date.formatted(style.year()))"
        }
        return DayHeadline(eyebrow: eyebrow, title: date.formatted(style.weekday(.wide)))
    }
}

/// The parts of the day screen, in order.
public enum DaySection: CaseIterable, Equatable, Sendable {
    case weather, agenda, checklist, readings, money, nudges
}

/// Which parts a day shows. A past day is a record without a forecast; a
/// day ahead is a plan without readings, spend or nudges; the forecast
/// reaches ten days.
public enum DaySections {
    public static let forecastDays = 10

    public static func visible(for placement: DayPlacement) -> [DaySection] {
        switch placement {
        case .past: [.agenda, .checklist, .readings, .money, .nudges]
        case .today: DaySection.allCases
        case .future(let days): days < forecastDays ? [.weather, .agenda, .checklist] : [.agenda, .checklist]
        }
    }
}
