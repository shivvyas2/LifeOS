import Testing
import Foundation
import SwiftData
import Persistence
@testable import Integrations

/// A scriptable source. `final class` with internal state guarded by
/// MainActor: every test and every CalendarSync call runs on MainActor.
@MainActor
final class FakeSource: CalendarSource, @unchecked Sendable {
    nonisolated let source: CalendarEventSource
    var authorized = true
    var fetchResult: Result<[CalendarEventSnapshot], Error> = .success([])
    var created: [CalendarEventDraft] = []
    var updated: [(sourceID: String, draft: CalendarEventDraft)] = []
    var deleted: [String] = []

    nonisolated init(source: CalendarEventSource) { self.source = source }

    var isAuthorized: Bool { authorized }
    func requestAccess() async throws -> Bool { authorized }
    func events(from: Date, to: Date) async throws -> [CalendarEventSnapshot] {
        try fetchResult.get()
    }
    func create(_ draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        created.append(draft)
        return snapshot(sourceID: "\(source.rawValue)-new-\(created.count)", draft: draft)
    }
    func update(sourceID: String, with draft: CalendarEventDraft) async throws -> CalendarEventSnapshot {
        updated.append((sourceID, draft))
        return snapshot(sourceID: sourceID, draft: draft)
    }
    func delete(sourceID: String) async throws { deleted.append(sourceID) }

    private func snapshot(sourceID: String, draft: CalendarEventDraft) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: UUID(), source: source, sourceID: sourceID,
            calendarTitle: "Cal", title: draft.title,
            startDate: draft.startDate, endDate: draft.endDate,
            isAllDay: draft.isAllDay, isRecurring: false,
            location: draft.location, notes: draft.notes
        )
    }
}

@Suite @MainActor struct CalendarSyncTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_756_209_600)

    private func make() throws -> (CalendarSync, CalendarStore, FakeSource, FakeSource) {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = CalendarStore(context: ModelContext(container), calendar: calendar)
        let eventKit = FakeSource(source: .eventKit)
        let google = FakeSource(source: .google)
        let sync = CalendarSync(sources: [eventKit, google], store: store,
                                calendar: calendar, now: { [now] in now })
        return (sync, store, eventKit, google)
    }

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

    @Test func aThrowingSourceDoesNotBlockTheOthers() async throws {
        let (sync, store, eventKit, google) = try make()
        eventKit.fetchResult = .failure(URLError(.notConnectedToInternet))
        google.fetchResult = .success([snapshot("Kept", source: .google, sourceID: "g-1", start: now)])

        await sync.sync()

        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Kept"])
    }

    @Test func anUnauthorizedSourceIsSkippedEntirely() async throws {
        let (sync, store, eventKit, google) = try make()
        google.authorized = false
        google.fetchResult = .success([snapshot("Hidden", source: .google, sourceID: "g-1", start: now)])
        eventKit.fetchResult = .success([snapshot("Shown", source: .eventKit, sourceID: "ek-1", start: now)])

        await sync.sync()

        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Shown"])
    }

    @Test func collidingEventsAcrossSourcesAreDeduplicatedEventKitFirst() async throws {
        let (sync, store, eventKit, google) = try make()
        eventKit.fetchResult = .success([snapshot("Standup", source: .eventKit, sourceID: "ek-1", start: now)])
        google.fetchResult = .success([snapshot("standup", source: .google, sourceID: "g-1", start: now)])

        await sync.sync()

        let events = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400))
        #expect(events.count == 1)
        #expect(events[0].source == .eventKit)
    }

    @Test func createDispatchesToTheFirstAuthorizedSourceAndResyncs() async throws {
        let (sync, store, eventKit, _) = try make()
        let draft = CalendarEventDraft(title: "Dentist", startDate: now, endDate: now.addingTimeInterval(3_600))
        // After the write, the provider fetch reflects the created event.
        eventKit.fetchResult = .success([snapshot("Dentist", source: .eventKit, sourceID: "ek-new-1", start: now)])

        try await sync.create(draft)

        #expect(eventKit.created.map(\.title) == ["Dentist"])
        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Dentist"])
    }

    @Test func createReturnsTheEventAsTheCacheHoldsIt() async throws {
        let (sync, store, eventKit, _) = try make()
        let draft = CalendarEventDraft(title: "Dentist", startDate: now, endDate: now.addingTimeInterval(3_600))
        // The fake's create answers with sourceID "eventKit-new-1" under a
        // throwaway id; the fetch after the write reports the same key under
        // another. The caller must get the one the cache kept.
        eventKit.fetchResult = .success([snapshot("Dentist", source: .eventKit, sourceID: "eventKit-new-1", start: now)])

        let created = try await sync.create(draft)

        let stored = try #require(try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).first)
        #expect(created.id == stored.id)
        #expect(created.title == "Dentist")
    }

    @Test func updateRoutesToTheSourceOwningTheEvent() async throws {
        let (sync, store, eventKit, google) = try make()
        google.fetchResult = .success([snapshot("Gym", source: .google, sourceID: "g-1", start: now)])
        await sync.sync()
        let id = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400))[0].id

        let moved = CalendarEventDraft(title: "Gym", startDate: now.addingTimeInterval(7_200), endDate: now.addingTimeInterval(10_800))
        google.fetchResult = .success([snapshot("Gym", source: .google, sourceID: "g-1", start: moved.startDate)])
        try await sync.update(id: id, with: moved)

        #expect(google.updated.map(\.sourceID) == ["g-1"])
        #expect(eventKit.updated.isEmpty)
    }

    @Test func aThrowingSourceKeepsItsPreviouslySyncedEvents() async throws {
        let (sync, store, eventKit, google) = try make()
        eventKit.fetchResult = .success([snapshot("Mine", source: .eventKit, sourceID: "ek-1", start: now)])
        google.fetchResult = .success([snapshot("Theirs", source: .google, sourceID: "g-1", start: now.addingTimeInterval(3_600))])
        await sync.sync()

        eventKit.fetchResult = .failure(URLError(.notConnectedToInternet))
        await sync.sync()

        let titles = try store.events(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(86_400)).map(\.title)
        #expect(titles == ["Mine", "Theirs"])
    }

    @Test func deleteOfAnUnknownIDThrows() async throws {
        let (sync, _, _, _) = try make()
        await #expect(throws: CalendarSyncError.unknownEvent) {
            try await sync.delete(id: UUID())
        }
    }
}
