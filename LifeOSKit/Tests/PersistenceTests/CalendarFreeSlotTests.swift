// LifeOSKit/Tests/PersistenceTests/CalendarFreeSlotTests.swift
import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite struct CalendarFreeSlotTests {
    private let dayStart = Date(timeIntervalSince1970: 1_756_166_400)
    private var dayEnd: Date { dayStart.addingTimeInterval(86_400) }
    private var day: DateInterval { DateInterval(start: dayStart, end: dayEnd) }

    private func busy(_ startHour: Double, _ endHour: Double) -> DateInterval {
        DateInterval(
            start: dayStart.addingTimeInterval(startHour * 3_600),
            end: dayStart.addingTimeInterval(endHour * 3_600)
        )
    }

    @Test func anEmptyDayIsOneFreeSlot() {
        let slots = CalendarStore.freeSlots(in: day, busy: [], durationMinutes: 30)
        #expect(slots == [day])
    }

    @Test func aFullyBookedDayHasNoSlots() {
        let slots = CalendarStore.freeSlots(in: day, busy: [busy(0, 24)], durationMinutes: 30)
        #expect(slots.isEmpty)
    }

    @Test func gapsShorterThanTheDurationAreNotOffered() {
        // Free 9-9:20 between meetings; a 30 minute ask must skip it.
        let slots = CalendarStore.freeSlots(
            in: DateInterval(start: busy(8, 9).start, end: busy(10, 11).end),
            busy: [busy(8, 9), busy(9.34, 10)],
            durationMinutes: 30
        )
        #expect(slots == [busy(10, 11)])
    }

    @Test func overlappingBusyIntervalsAreMergedBeforeSubtracting() {
        let slots = CalendarStore.freeSlots(
            in: day,
            busy: [busy(9, 11), busy(10, 12), busy(12, 13)],
            durationMinutes: 60
        )
        #expect(slots == [busy(0, 9), busy(13, 24)])
    }

    @Test func aKnownDayOfEventsYieldsTheExpectedGaps() {
        let slots = CalendarStore.freeSlots(
            in: day,
            busy: [busy(9, 9.5), busy(11, 12), busy(15, 16.5)],
            durationMinutes: 60
        )
        #expect(slots == [busy(0, 9), busy(9.5, 11), busy(12, 15), busy(16.5, 24)])
    }

    @Suite @MainActor struct StoreBacked {
        @Test func allDayEventsDoNotBlockTime() throws {
            let container = try LifeOSContainer.make(inMemory: true)
            let store = CalendarStore(context: ModelContext(container))
            let dayStart = Date(timeIntervalSince1970: 1_756_166_400)
            let window = DateInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
            let allDay = CalendarEventSnapshot(
                id: UUID(), source: .eventKit, sourceID: "ek-1",
                calendarTitle: "Cal", title: "Anniversary",
                startDate: dayStart, endDate: dayStart.addingTimeInterval(86_400),
                isAllDay: true, isRecurring: false, location: nil, notes: nil
            )
            try store.apply([allDay], window: window)

            let slots = try store.freeSlots(from: dayStart, to: window.end, durationMinutes: 30)
            #expect(slots == [window])
        }
    }
}
