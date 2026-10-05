import Foundation
import Testing
@testable import Persistence

@Suite struct NextUpTests {
    private func event(_ title: String, hour: Int, minutes: Int = 30, allDay: Bool = false) -> CalendarEventSnapshot {
        let day = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let start = day.addingTimeInterval(Double(hour) * 3600)
        return CalendarEventSnapshot(id: UUID(), source: .eventKit, sourceID: title, calendarTitle: "Work", title: title,
                                     startDate: start, endDate: start.addingTimeInterval(Double(minutes) * 60),
                                     isAllDay: allDay, isRecurring: false, location: nil, notes: nil)
    }
    private func at(_ hour: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour))!
    }

    /// At seven in the evening the morning standup is over: the next event is
    /// the first one still to come, and what is past is not listed.
    @Test func nextUpSkipsWhatHasEnded() {
        let agenda = [event("Standup", hour: 9), event("Lunch", hour: 12), event("Review", hour: 16)]
        let split = agenda.nextUp(now: at(13))
        #expect(split.next?.title == "Review")
        #expect(split.remaining.isEmpty)
        let morning = agenda.nextUp(now: at(8))
        #expect(morning.next?.title == "Standup")
        #expect(morning.remaining.map(\.title) == ["Lunch", "Review"])
    }

    @Test func anEventInProgressIsStillNext() {
        let agenda = [event("Standup", hour: 9), event("Lunch", hour: 12)]
        let split = agenda.nextUp(now: at(9).addingTimeInterval(600))
        #expect(split.next?.title == "Standup")
    }

    @Test func allDayEventsStayNextAllDay() {
        let agenda = [event("Offsite", hour: 0, allDay: true), event("Lunch", hour: 12)]
        #expect(agenda.nextUp(now: at(20)).next?.title == "Offsite")
    }

    @Test func nothingLeftWhenEverythingHasEnded() {
        let agenda = [event("Standup", hour: 9)]
        let split = agenda.nextUp(now: at(19))
        #expect(split.next == nil)
        #expect(split.remaining.isEmpty)
    }
}
