import Testing
import Foundation
@testable import DesignSystem

@Suite struct CalendarHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    @Test func monthlyNamesTheShownYearNotToday() {
        let h = CalendarHeadline.make(mode: .monthly, month: date(2027, 1, 15), selection: date(2026, 10, 6),
                                      calendar: calendar, locale: en)
        #expect(h.eyebrow == "Monthly · 2027")
        #expect(h.title == "Calendar")
        #expect(h.detail == nil)
    }

    @Test func weeklyFollowsTheSelection() {
        let h = CalendarHeadline.make(mode: .weekly, month: date(2026, 10, 1), selection: date(2026, 10, 6),
                                      calendar: calendar, locale: en)
        #expect(h.eyebrow == "Weekly · October")
        #expect(h.title == "Calendar")
        #expect(h.detail == "Oct 4 to Oct 10")
    }

    @Test func weeklyRangeCrossesMonths() {
        let h = CalendarHeadline.make(mode: .weekly, month: date(2026, 10, 1), selection: date(2026, 10, 1),
                                      calendar: calendar, locale: en)
        #expect(h.eyebrow == "Weekly · October")
        #expect(h.detail == "Sep 27 to Oct 3")
    }
}
