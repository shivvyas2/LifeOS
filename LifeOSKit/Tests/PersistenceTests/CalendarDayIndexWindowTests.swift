import Testing
import Foundation
@testable import Persistence

@Suite struct CalendarDayIndexWindowTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The calendar screen loads the shown month, the next, and a week either
    /// side. A day outside that is one the screen must move to, not merely
    /// select, or its week shows nothing.
    @Test func windowIsTwoMonthsPaddedByAWeek() throws {
        let window = try #require(CalendarDayIndex.window(forMonth: date(2026, 10, 15), calendar: calendar))
        #expect(window.start == date(2026, 9, 24))
        #expect(window.end == date(2026, 12, 8))
        #expect(window.contains(date(2026, 11, 30)))
        #expect(!window.contains(date(2027, 1, 14)))
        #expect(!window.contains(date(2026, 9, 23)))
    }
}
