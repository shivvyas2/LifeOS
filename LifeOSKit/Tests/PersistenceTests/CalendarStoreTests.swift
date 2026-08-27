import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct CalendarStoreTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeStore() throws -> CalendarStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return CalendarStore(context: ModelContext(container), calendar: calendar)
    }

    private func snapshot(
        _ title: String, sourceID: String, start: Date,
        minutes: Double = 60, source: CalendarEventSource = .eventKit,
        allDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: title,
            startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            isAllDay: allDay, isRecurring: false, location: nil, notes: nil
        )
    }

    /// Day 0 of every test, away from DST transitions.
    private var noon: Date { Date(timeIntervalSince1970: 1_756_209_600) }
    private var window: DateInterval {
        DateInterval(
            start: calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: noon))!,
            end: calendar.date(byAdding: .day, value: 90, to: calendar.startOfDay(for: noon))!
        )
    }

    @Test func applyingTheSameFetchTwiceDoesNotDuplicate() throws {
        let store = try makeStore()
        let fetched = [snapshot("Standup", sourceID: "ek-1", start: noon)]

        try store.apply(fetched, window: window)
        try store.apply(fetched, window: window)

        let events = try store.events(from: window.start, to: window.end)
        #expect(events.count == 1)
    }

    @Test func applyPreservesTheLocalIDOfAnExistingRow() throws {
        let store = try makeStore()
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        let firstID = try store.events(from: window.start, to: window.end)[0].id

        // A re-fetch produces a fresh provisional UUID for the same event.
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        let secondID = try store.events(from: window.start, to: window.end)[0].id
        #expect(firstID == secondID)
    }

    @Test func applyUpdatesChangedFieldsInPlace() throws {
        let store = try makeStore()
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        try store.apply([snapshot("Standup (moved)", sourceID: "ek-1", start: noon.addingTimeInterval(1_800))], window: window)

        let events = try store.events(from: window.start, to: window.end)
        #expect(events.count == 1)
        #expect(events[0].title == "Standup (moved)")
    }

    @Test func inWindowRowsAbsentFromAFetchAreDeleted() throws {
        let store = try makeStore()
        try store.apply([
            snapshot("Keep", sourceID: "ek-1", start: noon),
            snapshot("Gone", sourceID: "ek-2", start: noon.addingTimeInterval(7_200)),
        ], window: window)

        try store.apply([snapshot("Keep", sourceID: "ek-1", start: noon)], window: window)

        let titles = try store.events(from: window.start, to: window.end).map(\.title)
        #expect(titles == ["Keep"])
    }

    @Test func outOfWindowRowsSurviveAnApply() throws {
        let store = try makeStore()
        let past = calendar.date(byAdding: .day, value: -45, to: noon)!
        try store.apply([snapshot("Old", sourceID: "ek-old", start: past)],
                        window: DateInterval(start: past.addingTimeInterval(-86_400), end: past.addingTimeInterval(86_400)))

        try store.apply([snapshot("New", sourceID: "ek-1", start: noon)], window: window)

        let all = try store.events(
            from: calendar.date(byAdding: .day, value: -60, to: noon)!,
            to: window.end
        )
        #expect(all.map(\.title).sorted() == ["New", "Old"])
    }

    @Test func windowQueriesIncludeEventsOverlappingTheEdges() throws {
        let store = try makeStore()
        let dayStart = calendar.startOfDay(for: noon)
        // Started yesterday 23:30, runs into today.
        let spanning = snapshot("Redeye", sourceID: "ek-1", start: dayStart.addingTimeInterval(-1_800))
        // All-day today.
        let allDay = snapshot("Birthday", sourceID: "ek-2", start: dayStart, minutes: 24 * 60, allDay: true)
        // Ends exactly at the window start: excluded, a zero-length overlap is no overlap.
        let before = snapshot("Earlier", sourceID: "ek-3", start: dayStart.addingTimeInterval(-3_600))
        try store.apply([spanning, allDay, before], window: window)

        let today = try store.events(from: dayStart, to: dayStart.addingTimeInterval(86_400))
        #expect(today.map(\.title) == ["Redeye", "Birthday"])
    }

    @Test func snapshotByIDFindsTheRow() throws {
        let store = try makeStore()
        try store.apply([snapshot("Standup", sourceID: "ek-1", start: noon)], window: window)
        let id = try store.events(from: window.start, to: window.end)[0].id

        #expect(try store.snapshot(id: id)?.title == "Standup")
        #expect(try store.snapshot(id: UUID()) == nil)
    }

    @Test func aReschedulingIntoTheWindowReusesTheExistingRow() throws {
        let store = try makeStore()
        let past = calendar.date(byAdding: .day, value: -45, to: noon)!
        let pastWindow = DateInterval(start: past.addingTimeInterval(-86_400), end: past.addingTimeInterval(86_400))
        try store.apply([snapshot("Review", sourceID: "ek-1", start: past)], window: pastWindow)
        let originalID = try store.events(from: pastWindow.start, to: pastWindow.end)[0].id

        // The provider reschedules the same event into the current window.
        try store.apply([snapshot("Review", sourceID: "ek-1", start: noon)], window: window)

        let wide = try store.events(from: calendar.date(byAdding: .day, value: -60, to: noon)!, to: window.end)
        #expect(wide.count == 1)
        #expect(wide[0].id == originalID)
        #expect(wide[0].startDate == noon)
    }

    @Test func pruningOnlyTouchesAuthoritativeSources() throws {
        let store = try makeStore()
        try store.apply([
            snapshot("Mine", sourceID: "ek-1", start: noon),
            snapshot("Theirs", sourceID: "g-1", start: noon, source: .google),
        ], window: window)

        // EventKit reports fresh (empty) data; Google was not fetched at all.
        try store.apply([], window: window, authoritative: [.eventKit])

        let titles = try store.events(from: window.start, to: window.end).map(\.title)
        #expect(titles == ["Theirs"])
    }
}

@Suite @MainActor struct CalendarEventsByIDTests {

    private func snapshot(_ title: String, _ sourceID: String) -> CalendarEventSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: sourceID,
            calendarTitle: "Work", title: title,
            startDate: now, endDate: now.addingTimeInterval(1800),
            isAllDay: false, isRecurring: false, location: nil, notes: nil
        )
    }

    /// The lookup behind the cards under an assistant reply.
    @Test func onlyTheAskedForEventsComeBack() throws {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        let store = CalendarStore(context: context)

        let wanted = snapshot("Standup", "a")
        context.insert(CalendarEvent(from: wanted))
        context.insert(CalendarEvent(from: snapshot("Lunch", "b")))
        try context.save()

        #expect(try store.events(withIDs: [wanted.id]).map(\.id) == [wanted.id])
    }

    /// An event deleted since the reply was written must simply be absent, so
    /// the card disappears rather than describing something that is gone.
    @Test func anUnknownIdIsAbsentRatherThanAnError() throws {
        let store = CalendarStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
        #expect(try store.events(withIDs: [UUID()]).isEmpty)
        #expect(try store.events(withIDs: []).isEmpty)
    }
}
