// LifeOSKit/Tests/AssistantTests/CalendarToolsTests.swift
import Testing
import Foundation
import FoundationModels
import Insights
import Persistence
@testable import Assistant

@MainActor
private final class FakeCalendar: CalendarReading, CalendarWriting, @unchecked Sendable {
    var stored: [CalendarEventSnapshot] = []
    var slots: [DateInterval] = []
    private(set) var created: [CalendarEventDraft] = []
    private(set) var updated: [(id: UUID, draft: CalendarEventDraft)] = []
    private(set) var deleted: [UUID] = []

    nonisolated init() {}

    func events(from: Date, to: Date) throws -> [CalendarEventSnapshot] {
        stored.filter { $0.startDate < to && $0.endDate > from }
    }
    func snapshot(id: UUID) throws -> CalendarEventSnapshot? {
        stored.first { $0.id == id }
    }
    func freeSlots(from: Date, to: Date, durationMinutes: Int) throws -> [DateInterval] {
        slots
    }
    nonisolated func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        await MainActor.run {
            created.append(draft)
            return CalendarEventSnapshot(
                id: UUID(), source: .eventKit, sourceID: "ek-created-\(created.count)",
                calendarTitle: "Cal", title: draft.title,
                startDate: draft.startDate, endDate: draft.endDate,
                isAllDay: draft.isAllDay, isRecurring: false,
                location: draft.location, notes: draft.notes
            )
        }
    }
    nonisolated func update(id: UUID, with draft: CalendarEventDraft) async throws {
        await MainActor.run { updated.append((id, draft)) }
    }
    nonisolated func delete(id: UUID) async throws {
        await MainActor.run { deleted.append(id) }
    }
}

@Suite @MainActor struct CalendarToolsTests {
    // 2026-08-26T12:00:00Z, so it falls inside the 2026-08-26/27 ranges the
    // tests below query. (The brief's literal 1_756_209_600 is 2025-08-26,
    // a year off from the query ranges used everywhere in this file, which
    // silently defeats getEventsReturnsIDsAndTitlesInTheRange -- the only
    // test here that actually filters by date rather than looking up by id.)
    private let noon = Date(timeIntervalSince1970: 1_787_745_600)

    private func event(_ title: String, id: UUID = UUID(), recurring: Bool = false) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id, source: .eventKit, sourceID: "ek-\(title)",
            calendarTitle: "Cal", title: title,
            startDate: noon, endDate: noon.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: recurring, location: nil, notes: nil
        )
    }

    private func tool(named name: String, on fake: FakeCalendar) throws -> any CoachTool {
        let tools = CalendarAssistant.tools(reading: fake, writing: fake)
        return try #require(tools.first { $0.name == name })
    }

    /// `GeneratedContent(properties:)` takes a `KeyValuePairs`, which has no
    /// runtime initializer from a `Dictionary`, so a literal argument bag
    /// can't be built the way the brief's helper does it. Route through
    /// `GeneratedContent(json:)` instead, with a light heuristic so
    /// `Bool`/`Int` `@Generable` fields see real JSON types rather than the
    /// strings "false"/"30" (a `GeneratedContent` holding a string does not
    /// coerce into a `Bool` or `Int` field). Call sites and assertions are
    /// unchanged.
    private func arguments(_ pairs: [String: String]) -> GeneratedContent {
        var object: [String: Any] = [:]
        for (key, value) in pairs {
            if let intValue = Int(value) {
                object[key] = intValue
            } else if value == "true" || value == "false" {
                object[key] = (value == "true")
            } else {
                object[key] = value
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! GeneratedContent(json: String(data: data, encoding: .utf8)!)
    }

    @Test func thereAreSixToolsAndOnlyWritesAreGated() throws {
        let fake = FakeCalendar()
        let tools = CalendarAssistant.tools(reading: fake, writing: fake)
        #expect(tools.map(\.name).sorted() == [
            "analyze_schedule", "create_event", "delete_event",
            "find_free_time", "get_events", "update_event",
        ])
        #expect(tools.filter(\.requiresConfirmation).map(\.name).sorted() == ["delete_event", "update_event"])
    }

    @Test func getEventsReturnsIDsAndTitlesInTheRange() async throws {
        let fake = FakeCalendar()
        let mine = event("Standup")
        fake.stored = [mine]
        let result = try await tool(named: "get_events", on: fake).call(arguments([
            "start": "2026-08-26T00:00:00Z", "end": "2026-08-27T00:00:00Z",
        ]))
        #expect(result.contains("Standup"))
        #expect(result.contains(mine.id.uuidString))
    }

    @Test func aGarbledDateIsAThrownErrorNotACrash() async throws {
        let fake = FakeCalendar()
        await #expect(throws: (any Error).self) {
            _ = try await tool(named: "get_events", on: fake).call(arguments([
                "start": "yesterday-ish", "end": "2026-08-27T00:00:00Z",
            ]))
        }
    }

    @Test func findFreeTimeReportsTheSlots() async throws {
        let fake = FakeCalendar()
        fake.slots = [DateInterval(start: noon, duration: 3_600)]
        let result = try await tool(named: "find_free_time", on: fake).call(arguments([
            "start": "2026-08-26T00:00:00Z", "end": "2026-08-27T00:00:00Z",
            "durationMinutes": "30",
        ]))
        #expect(result.contains("free"))
    }

    @Test func createEventMapsItsArgumentsOntoTheDraft() async throws {
        let fake = FakeCalendar()
        _ = try await tool(named: "create_event", on: fake).call(arguments([
            "title": "Dentist", "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "12 Main St", "notes": "",
        ]))
        #expect(fake.created.count == 1)
        #expect(fake.created[0].title == "Dentist")
        #expect(fake.created[0].location == "12 Main St")
        #expect(fake.created[0].notes == nil)
    }

    @Test func createEventRecordsTheNewEventForTheReplyCard() async throws {
        let fake = FakeCalendar()
        let collector = CalendarEventCollector()
        let tools = CalendarAssistant.tools(reading: fake, writing: fake, collector: collector)
        let create = try #require(tools.first { $0.name == "create_event" })
        _ = try await create.call(arguments([
            "title": "Dentist", "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))
        let collected = await collector.collected()
        #expect(collected.map(\.title) == ["Dentist"])
    }

    @Test func updateRejectsAnUnknownID() async throws {
        let fake = FakeCalendar()
        let result = try await tool(named: "update_event", on: fake).call(arguments([
            "id": UUID().uuidString, "title": "X",
            "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))
        #expect(result.contains("No event"))
        #expect(fake.updated.isEmpty)
    }

    @Test func writesToARecurringEventAreRefusedWithAnExplanation() async throws {
        let fake = FakeCalendar()
        let series = event("Standup", recurring: true)
        fake.stored = [series]

        let update = try await tool(named: "update_event", on: fake).call(arguments([
            "id": series.id.uuidString, "title": "Standup",
            "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))
        let delete = try await tool(named: "delete_event", on: fake).call(arguments([
            "id": series.id.uuidString,
        ]))

        #expect(update.contains("recurring"))
        #expect(delete.contains("recurring"))
        #expect(fake.updated.isEmpty)
        #expect(fake.deleted.isEmpty)
    }

    @Test func deleteDispatchesForAKnownOneOffEvent() async throws {
        let fake = FakeCalendar()
        let mine = event("Old plan")
        fake.stored = [mine]
        _ = try await tool(named: "delete_event", on: fake).call(arguments([
            "id": mine.id.uuidString,
        ]))
        #expect(fake.deleted == [mine.id])
    }

    @Test func confirmationPreviewShowsTheCurrentEvent() async throws {
        let fake = FakeCalendar()
        let mine = event("Gym")
        fake.stored = [mine]
        let preview = try await tool(named: "delete_event", on: fake).confirmationPreview(arguments([
            "id": mine.id.uuidString,
        ]))
        #expect(preview.joined(separator: "\n").contains("Gym"))
    }

    /// The update is a full replacement, so a model that omits the location
    /// silently erases it. The card must say so before anyone confirms.
    @Test func updatePreviewCallsOutADroppedLocation() async throws {
        let fake = FakeCalendar()
        let mine = CalendarEventSnapshot(
            id: UUID(), source: .eventKit, sourceID: "ek-loc",
            calendarTitle: "Cal", title: "Dentist",
            startDate: noon, endDate: noon.addingTimeInterval(3_600),
            isAllDay: false, isRecurring: false,
            location: "12 Main St", notes: nil
        )
        fake.stored = [mine]

        let preview = try await tool(named: "update_event", on: fake).confirmationPreview(arguments([
            "id": mine.id.uuidString, "title": "Dentist",
            "start": "2026-08-26T12:00:00Z", "end": "2026-08-26T13:00:00Z",
            "isAllDay": "false", "location": "", "notes": "",
        ]))

        #expect(preview.joined(separator: "\n").contains("12 Main St"))
        #expect(preview.contains { $0.contains("Removes the location") })
    }
}
