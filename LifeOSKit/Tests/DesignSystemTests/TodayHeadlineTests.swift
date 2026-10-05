import Testing
import Foundation
@testable import DesignSystem

@Suite struct TodayHeadlineTests {
    private let en = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func date(_ d: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    @Test func todayNamesTheDayAndGreetsByHour() {
        let h = TodayHeadline.make(date: date(5), now: date(5, hour: 9), streak: 6, calendar: calendar, locale: en)
        #expect(h.eyebrow == "Today · Monday, Oct 5")
        #expect(h.title == "Good morning")
        #expect(h.detail == "6-day streak")
        #expect(TodayHeadline.make(date: date(5), now: date(5, hour: 14), streak: 6, calendar: calendar, locale: en).title == "Good afternoon")
        #expect(TodayHeadline.make(date: date(5), now: date(5, hour: 19), streak: 6, calendar: calendar, locale: en).title == "Good evening")
    }

    @Test func pastDayHasNoWeekday() {
        let h = TodayHeadline.make(date: date(3), now: date(5), streak: 6, calendar: calendar, locale: en)
        #expect(h.eyebrow == "Oct 3")
        #expect(h.title == "Saturday")
    }

    @Test func streakWording() {
        #expect(TodayHeadline.make(date: date(5), now: date(5), streak: 1, calendar: calendar, locale: en).detail == "1-day streak")
        #expect(TodayHeadline.make(date: date(5), now: date(5), streak: 0, calendar: calendar, locale: en).detail == "Start a streak today")
    }
}
