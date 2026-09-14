import Foundation
import Testing
@testable import Persistence

struct CalendarDayIndexTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }
    private func event(from: Date, to: Date) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: "test", calendarTitle: "Home",
                              title: "Trip", startDate: from, endDate: to, isAllDay: true,
                              isRecurring: false, location: nil, notes: nil)
    }
    @Test func spansEveryDayAcrossDaylightSavingWithoutIncludingExclusiveEnd() {
        let event = event(from: date(7), to: date(10))
        let days = CalendarDayIndex.group([event], from: date(1), to: date(31), calendar: calendar)
        #expect(Set(days.keys) == Set([date(7), date(8), date(9)]))
        #expect(days.values.allSatisfy { $0 == [event] })
    }
    @Test func overnightEventAppearsOnBothDays() {
        let event = event(from: date(12, hour: 23), to: date(13, hour: 1))
        let days = CalendarDayIndex.group([event], from: date(12), to: date(14), calendar: calendar)
        #expect(Set(days.keys) == Set([date(12), date(13)]))
    }
    @Test func clipsLongEventsToVisibleWindowAndExcludesOutsideEvents() {
        let spanning = event(from: date(1), to: date(20))
        let outside = event(from: date(3), to: date(4))
        let days = CalendarDayIndex.group([spanning, outside], from: date(10), to: date(12), calendar: calendar)
        #expect(Set(days.keys) == Set([date(10), date(11)]))
        #expect(days.values.allSatisfy { $0 == [spanning] })
    }
}
