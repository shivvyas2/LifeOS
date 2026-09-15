import Foundation
import Testing
@testable import AppSurfaces

struct AgendaSnapshotTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        result.firstWeekday = 2
        return result
    }
    /// 2027-01-15 12:00 UTC, a Friday.
    private var noon: Date { Date(timeIntervalSince1970: 1_800_014_400) }
    private func at(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: noon))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }
    private func event(_ title: String, start: Date, end: Date, allDay: Bool = false, calendarTitle: String = "Work") -> AgendaSnapshot.Event {
        AgendaSnapshot.Event(id: UUID(), title: title, calendarTitle: calendarTitle, startDate: start, endDate: end, isAllDay: allDay)
    }

    @Test func weekStartsOnTheCalendarWeekAndCoversSevenDays() {
        let value = AgendaSnapshot(ownerID: "a", generatedAt: noon, calendar: calendar)
        let days = value.weekDays(calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first == at(dayOffset: -4, hour: 0))
        #expect(days.last == at(dayOffset: 2, hour: 0))
        #expect(value.weekStart == days.first)
    }

    @Test func eventsOnADayPutAllDayFirstAndIncludeOverlaps() {
        let allDay = event("Trip", start: at(dayOffset: 0, hour: 0), end: at(dayOffset: 2, hour: 0), allDay: true)
        let morning = event("Gym", start: at(dayOffset: 0, hour: 7), end: at(dayOffset: 0, hour: 8))
        let late = event("Dinner", start: at(dayOffset: 0, hour: 19), end: at(dayOffset: 0, hour: 20))
        let tomorrow = event("Standup", start: at(dayOffset: 1, hour: 9), end: at(dayOffset: 1, hour: 10))
        let value = AgendaSnapshot(ownerID: "a", generatedAt: noon, events: [late, tomorrow, morning, allDay], calendar: calendar)
        let today = value.events(on: at(dayOffset: 0, hour: 0), calendar: calendar).map(\.title)
        #expect(today == ["Trip", "Gym", "Dinner"])
        let next = value.events(on: at(dayOffset: 1, hour: 0), calendar: calendar).map(\.title)
        #expect(next == ["Trip", "Standup"])
    }

    @Test func upcomingSkipsEndedKeepsInProgressAndRespectsLimit() {
        let ended = event("Gym", start: at(dayOffset: 0, hour: 7), end: at(dayOffset: 0, hour: 8))
        let running = event("Sync", start: at(dayOffset: 0, hour: 11), end: at(dayOffset: 0, hour: 13))
        let later = event("Lunch", start: at(dayOffset: 0, hour: 13), end: at(dayOffset: 0, hour: 14))
        let evening = event("Networking", start: at(dayOffset: 0, hour: 18), end: at(dayOffset: 0, hour: 19))
        let value = AgendaSnapshot(ownerID: "a", generatedAt: noon, events: [ended, running, later, evening], calendar: calendar)
        #expect(value.upcoming(from: noon, limit: 2).map(\.title) == ["Sync", "Lunch"])
        #expect(value.upcoming(from: noon).map(\.title) == ["Sync", "Lunch", "Networking"])
    }

    @Test func eventsAreSortedAndCappedKeepingTheEarliest() {
        let events = (0..<100).reversed().map { i in
            event("E\(i)", start: at(dayOffset: 0, hour: 0).addingTimeInterval(Double(i) * 600), end: at(dayOffset: 0, hour: 0).addingTimeInterval(Double(i) * 600 + 300))
        }
        let value = AgendaSnapshot(ownerID: "a", generatedAt: noon, events: events, calendar: calendar)
        #expect(value.events.count == AgendaSnapshot.eventCap)
        #expect(value.events.first?.title == "E0")
        #expect(value.events.last?.title == "E\(AgendaSnapshot.eventCap - 1)")
    }

    @Test func expiryFollowsHealthRulesAndTombstoneClearsOwnerAndEvents() throws {
        let value = AgendaSnapshot(ownerID: "a", generatedAt: noon, events: [event("Gym", start: noon, end: noon.addingTimeInterval(3600))], calendar: calendar)
        #expect(value.isAvailable(at: noon))
        #expect(!value.isAvailable(at: value.expiresAt))
        #expect(value.expiresAt == noon.addingTimeInterval(6 * 3600))
        let beforeMidnight = calendar.startOfDay(for: noon).addingTimeInterval(86300)
        #expect(AgendaSnapshot(ownerID: "a", generatedAt: beforeMidnight, calendar: calendar).expiresAt.timeIntervalSince(beforeMidnight) == 100)

        let suite = "test.agenda.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        value.write(to: defaults)
        #expect(AgendaSnapshot.read(from: defaults)?.events.count == 1)
        AgendaSnapshot(generatedAt: noon.addingTimeInterval(1)).write(to: defaults)
        let cleared = try #require(AgendaSnapshot.read(from: defaults))
        #expect(cleared.ownerID == nil && cleared.events.isEmpty)
        #expect(!cleared.isAvailable(at: noon.addingTimeInterval(1)))
    }

    @Test func chipPaletteIsStableAndBounded() {
        let names = ["Work", "Personal", "Family", "shiv@example.com", "", "Gym 🏋️"]
        for name in names {
            let index = ChipPalette.index(for: name)
            #expect(index == ChipPalette.index(for: name))
            #expect((0..<ChipPalette.count).contains(index))
        }
        #expect(ChipPalette.index(for: "Work") != ChipPalette.index(for: "Personal"))
    }
}
