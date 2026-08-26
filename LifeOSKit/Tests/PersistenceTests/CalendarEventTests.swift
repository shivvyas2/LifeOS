import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CalendarEventTests {
    @Test func aStoredEventRoundTripsThroughItsSnapshot() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)

        let start = Date(timeIntervalSince1970: 1_756_200_000)
        let snapshot = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-1",
            calendarTitle: "Home", title: "Dentist",
            startDate: start, endDate: start.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false,
            location: "12 Main St", notes: "bring card"
        )
        context.insert(CalendarEvent(from: snapshot))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CalendarEvent>())
        #expect(fetched.count == 1)
        #expect(fetched[0].snapshot() == snapshot)
    }

    @Test func anUnknownSourceRawFallsBackToEventKit() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_756_200_000)
        let event = CalendarEvent(from: CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "x",
            calendarTitle: "c", title: "t",
            startDate: start, endDate: start.addingTimeInterval(60),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        ))
        event.sourceRaw = "outlook"
        context.insert(event)
        #expect(event.source == .eventKit)
    }
}
