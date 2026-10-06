import Testing
import Foundation
@testable import Persistence

@Suite struct ScheduleSearchTests {
    private let noon = Date(timeIntervalSince1970: 1_791_900_000)

    private func event(_ title: String, id: UUID = UUID(), at offset: TimeInterval = 0,
                       location: String? = nil, calendar: String = "Work") -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, source: .eventKit, sourceID: title, calendarTitle: calendar, title: title,
            startDate: noon.addingTimeInterval(offset), endDate: noon.addingTimeInterval(offset + 3_600),
            isAllDay: false, isRecurring: false, location: location, notes: nil
        )
    }

    @Test func matchesIgnoreCaseAndDiacritics() {
        let events = [event("Dentist"), event("Café with Ana")]
        #expect(ScheduleSearch.matches("DENT", in: events).map(\.title) == ["Dentist"])
        #expect(ScheduleSearch.matches("cafe", in: events).map(\.title) == ["Café with Ana"])
    }

    @Test func aPlaceOrACalendarNameIsEnough() {
        let events = [event("Standup", location: "Room 4"), event("Birthday", calendar: "Family")]
        #expect(ScheduleSearch.matches("room 4", in: events).map(\.title) == ["Standup"])
        #expect(ScheduleSearch.matches("family", in: events).map(\.title) == ["Birthday"])
    }

    @Test func anEmptyOrBlankQueryMatchesNothing() {
        let events = [event("Dentist")]
        #expect(ScheduleSearch.matches("", in: events).isEmpty)
        #expect(ScheduleSearch.matches("   ", in: events).isEmpty)
    }

    @Test func resultsAreByStartThenTitleAndOncePerID() {
        // The day index hands a multi-day event back once per day it covers;
        // the person should see it once.
        let shared = UUID()
        let events = [
            event("Zoo day", id: shared, at: 0),
            event("Zoo day", id: shared, at: 0),
            event("Dentist", at: 86_400),
            event("Dinner", at: -86_400),
            event("Dance", at: -86_400),
        ]
        #expect(ScheduleSearch.matches("d", in: events).map(\.title) == ["Dance", "Dinner", "Zoo day", "Dentist"])
    }
}
