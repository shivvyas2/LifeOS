import Testing
import Foundation
@testable import DesignSystem

@Suite struct ScheduleFindTextTests {
    private let us = Locale(identifier: "en_US")
    private let gb = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func eyebrowCountsOrSaysNothingFound() {
        #expect(ScheduleFindText.eyebrow(found: 0) == "Nothing found")
        #expect(ScheduleFindText.eyebrow(found: 1) == "Found 1")
        #expect(ScheduleFindText.eyebrow(found: 3) == "Found 3")
    }

    @Test func scopeNamesTheShownMonthsAcrossAYearBoundary() {
        #expect(ScheduleFindText.scope(months: [date(2026, 10, 1), date(2026, 11, 1)], calendar: calendar, locale: us)
                == "In October and November. Ask for anything further out.")
        #expect(ScheduleFindText.scope(months: [date(2026, 12, 1), date(2027, 1, 1)], calendar: calendar, locale: us)
                == "In December and January. Ask for anything further out.")
    }

    @Test func overflowLine() {
        #expect(ScheduleFindText.more(4) == "4 more")
        #expect(ScheduleFindText.more(1) == "1 more")
    }

    @Test func rowLabelPutsTheWeekdayFirstAndFollowsTheDeviceClock() {
        // 13 October 2026 is a Tuesday. en_US would print the day before
        // the weekday if the two were one format; they are two.
        let start = date(2026, 10, 13, hour: 10)
        #expect(ScheduleFindText.rowLabel(start: start, isAllDay: false, calendar: calendar, locale: gb) == "Tue 13 · 10:00")
        #expect(ScheduleFindText.rowLabel(start: start, isAllDay: false, calendar: calendar, locale: us).hasPrefix("Tue 13 · 10:00"))
        #expect(ScheduleFindText.rowLabel(start: start, isAllDay: true, calendar: calendar, locale: us) == "All day")
    }
}
