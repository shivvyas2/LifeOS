import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CalendarStoreLookupTests {
    /// The id a provider hands back from a write is provisional; the row
    /// the sync wrote is the one the app can find by id, and this is how a
    /// caller gets to it.
    @Test func aRowIsFoundByItsSourceKeyUnderTheStoredID() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = CalendarStore(context: ModelContext(container))
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let fetched = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-9", calendarTitle: "Cal", title: "Dentist",
            startDate: now, endDate: now.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
        try store.apply([fetched], window: DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400)))

        let found = try #require(try store.snapshot(source: .eventKit, sourceID: "ek-9"))
        #expect(found.id == fetched.id)
        #expect(found.title == "Dentist")
        #expect(try store.snapshot(source: .google, sourceID: "ek-9") == nil)
    }
}
