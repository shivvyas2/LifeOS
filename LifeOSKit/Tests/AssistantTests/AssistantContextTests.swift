// LifeOSKit/Tests/AssistantTests/AssistantContextTests.swift
import Testing
import Foundation
import Persistence
@testable import Assistant

@Suite struct AssistantContextTests {
    private let noon = Date(timeIntervalSince1970: 1_756_209_600)

    @Test func unauthorizedInstructionsSayThereAreNoCalendarTools() {
        let text = CalendarAssistant.instructions(authorized: false)
        #expect(text.contains("no calendar"))
    }

    @Test func theContextPrefixInlinesTodayAndTomorrow() {
        let event = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-1",
            calendarTitle: "Cal", title: "Standup",
            startDate: noon, endDate: noon.addingTimeInterval(1_800),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
        let prefix = CalendarAssistant.contextPrefix(
            now: noon, timeZone: TimeZone(identifier: "UTC")!,
            today: [event], tomorrow: []
        )
        #expect(prefix.contains("Standup"))
        #expect(prefix.contains("Tomorrow: nothing scheduled"))
        #expect(prefix.contains("UTC"))
    }
}
