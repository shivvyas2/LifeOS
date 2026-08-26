import Testing
import Foundation
import Persistence
@testable import Integrations

@Suite struct CalendarMergeTests {
    private let start = Date(timeIntervalSince1970: 1_756_200_000)

    private func snapshot(
        _ title: String, source: CalendarEventSource, sourceID: String, start: Date
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: title,
            startDate: start, endDate: start.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
    }

    @Test func aCollisionOnTitleAndStartKeepsTheEventKitCopy() {
        let merged = CalendarMerge.merge(
            eventKit: [snapshot("Standup", source: .eventKit, sourceID: "ek-1", start: start)],
            google: [snapshot("standup", source: .google, sourceID: "g-1", start: start)]
        )
        #expect(merged.count == 1)
        #expect(merged[0].source == .eventKit)
    }

    @Test func theTitleMatchIsCaseInsensitiveButTheStartMustBeEqual() {
        let merged = CalendarMerge.merge(
            eventKit: [snapshot("Standup", source: .eventKit, sourceID: "ek-1", start: start)],
            google: [snapshot("Standup", source: .google, sourceID: "g-1", start: start.addingTimeInterval(60))]
        )
        #expect(merged.count == 2)
    }

    @Test func nonCollidingEventsFromBothSourcesAllSurvive() {
        let merged = CalendarMerge.merge(
            eventKit: [snapshot("A", source: .eventKit, sourceID: "ek-1", start: start)],
            google: [snapshot("B", source: .google, sourceID: "g-1", start: start)]
        )
        #expect(merged.map(\.title).sorted() == ["A", "B"])
    }
}
