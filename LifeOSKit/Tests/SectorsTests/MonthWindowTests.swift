import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct MonthWindowTests {

    /// Fixed, not `.current`: a month boundary test that used the machine's
    /// calendar would pass or fail depending on where it runs.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func theWindowSpansExactlyOneCalendarMonth() {
        let window = MonthWindow(for: date(2026, 8, 15), calendar: calendar)
        #expect(window.start == date(2026, 8, 1))
        #expect(window.end == date(2026, 9, 1))
        #expect(window.lastDay == date(2026, 8, 31))
        #expect(window.daysInMonth == 31)
    }

    @Test func februaryInALeapYearHasTwentyNineDays() {
        let window = MonthWindow(for: date(2028, 2, 10), calendar: calendar)
        #expect(window.daysInMonth == 29)
    }

    @Test func theFirstInstantOfTheMonthIsIncluded() {
        let window = MonthWindow(for: date(2026, 8, 15), calendar: calendar)
        #expect(window.contains(date(2026, 8, 1, 0, 0, 0)))
    }

    /// One second before the month starts must not count.
    @Test func anInstantJustBeforeTheMonthIsExcluded() {
        let window = MonthWindow(for: date(2026, 8, 15), calendar: calendar)
        #expect(!window.contains(date(2026, 7, 31, 23, 59, 59)))
    }

    /// The last instant of the last day must still count.
    @Test func theLastInstantOfTheMonthIsIncluded() {
        let window = MonthWindow(for: date(2026, 8, 15), calendar: calendar)
        #expect(window.contains(date(2026, 8, 31, 23, 59, 59)))
    }

    /// Midnight rolling into next month must not count: `end` is exclusive.
    @Test func anInstantJustAfterTheMonthIsExcluded() {
        let window = MonthWindow(for: date(2026, 8, 15), calendar: calendar)
        #expect(!window.contains(date(2026, 9, 1, 0, 0, 0)))
    }

    private struct Stamped { let date: Date }

    @Test func filterKeepsOnlyWhatFallsInsideTheWindow() {
        let window = MonthWindow(for: date(2026, 8, 15), calendar: calendar)
        let items = [
            Stamped(date: date(2026, 7, 31, 23, 59, 59)),  // just outside
            Stamped(date: date(2026, 8, 1, 0, 0, 0)),       // just inside
            Stamped(date: date(2026, 8, 31, 23, 59, 59)),   // just inside
            Stamped(date: date(2026, 9, 1, 0, 0, 0)),       // just outside
        ]
        let kept = window.filter(items, on: \.date)
        #expect(kept.count == 2)
    }
}
