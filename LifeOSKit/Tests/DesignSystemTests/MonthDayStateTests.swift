import Testing
import Foundation
import SwiftUI
@testable import DesignSystem

@Suite struct MonthDayStateTests {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = firstWeekday; return c
    }
    private func date(_ d: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour, minute: minute))!
    }

    @Test func todayIsTodayUntilMidnight() {
        let today = date(5, hour: 23, minute: 59)
        #expect(MonthDayState.of(date(5), today: today, calendar: calendar()) == .today)
        #expect(MonthDayState.of(date(4, hour: 23, minute: 59), today: today, calendar: calendar()) == .past)
        #expect(MonthDayState.of(date(6), today: today, calendar: calendar()) == .future)
    }

    /// Sunday first in en_US, Monday first in en_GB: the week is the calendar's.
    @Test func weekFollowsTheCalendar() {
        let wednesday = date(7)
        let sundayFirst = WeekSpan.days(containing: wednesday, calendar: calendar(firstWeekday: 1))
        let mondayFirst = WeekSpan.days(containing: wednesday, calendar: calendar(firstWeekday: 2))
        #expect(sundayFirst.count == 7 && mondayFirst.count == 7)
        #expect(sundayFirst.first == date(4))
        #expect(mondayFirst.first == date(5))
        #expect(sundayFirst.contains(wednesday) && mondayFirst.contains(wednesday))
    }

    @Test func hatchDrawsInsideItsCell() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 48)
        let path = HatchedCell().path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect))
    }
}
