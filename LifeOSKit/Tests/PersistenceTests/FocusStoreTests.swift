import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite struct FocusStoreTests {
    @MainActor @Test func focusedTimeAddsUpForTheDayOnly() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9))!
        try store.record(mood: "focus", source: "soundscape", startedAt: day, endedAt: day.addingTimeInterval(3000),
                         focusedSeconds: 3000, blocksCompleted: 2, projectTaskID: nil)
        try store.record(mood: "brainstorm", source: "appleMusic", startedAt: day.addingTimeInterval(7200),
                         endedAt: day.addingTimeInterval(9000), focusedSeconds: 1500, blocksCompleted: 1, projectTaskID: UUID())
        try store.record(mood: "focus", source: "silence", startedAt: day.addingTimeInterval(-86_400),
                         endedAt: nil, focusedSeconds: 900, blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.focusedSeconds(on: day, calendar: cal) == 4500)
    }

    @MainActor @Test func sleepIsNotFocusedTime() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "sleep", source: "soundscape", startedAt: .now, endedAt: .now, focusedSeconds: 1800,
                         blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.focusedSeconds(on: .now) == 0)
    }

    // MARK: - Sync bookkeeping

    private static let day: Date = {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9))!
    }()
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    @MainActor @Test func pendingExcludesUnfinished() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day.addingTimeInterval(600),
                         focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: nil,
                         focusedSeconds: 0, blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.pending().count == 1)
    }

    @MainActor @Test func markSyncedRemovesFromPending() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day.addingTimeInterval(600),
                         focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        try store.markSynced(ids: try store.pending().map(\.id))
        #expect(try store.pending().isEmpty)
    }

    @MainActor @Test func mergeSkipsKnownIDs() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day.addingTimeInterval(600),
                         focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        let local = try #require(try store.pending().first)
        let known = FocusSessionSnapshot(id: local.id, mood: "relax", source: "silence", startedAt: local.startedAt,
                                         endedAt: local.endedAt, focusedSeconds: 1, blocksCompleted: 0, projectTaskID: nil)
        let fresh = FocusSessionSnapshot(id: UUID(), mood: "focus", source: "appleMusic",
                                         startedAt: Self.day.addingTimeInterval(3600), endedAt: Self.day.addingTimeInterval(3900),
                                         focusedSeconds: 300, blocksCompleted: 1, projectTaskID: nil)
        #expect(try store.merge(remote: [known, fresh]) == 1)
        #expect(local.mood == "focus")
        #expect(try store.focusedSeconds(on: Self.day, calendar: Self.utc) == 900)
        // The merged row arrives synced; only this device's own record waits.
        #expect(try store.pending().count == 1)
    }

    @MainActor @Test func recentIsEmptyForANewStore() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        #expect(try FocusStore(context: container.mainContext).recent().isEmpty)
    }

    @MainActor @Test func recentIsNewestFirstAndFinishedOnly() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day.addingTimeInterval(600),
                         focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "relax", source: "silence", startedAt: Self.day.addingTimeInterval(3600),
                         endedAt: Self.day.addingTimeInterval(4200), focusedSeconds: 600, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day.addingTimeInterval(7200), endedAt: nil,
                         focusedSeconds: 0, blocksCompleted: 0, projectTaskID: nil)
        #expect(try store.recent().map(\.mood) == ["relax", "focus"])
    }

    @MainActor @Test func weekTotalSkipsSleepAndOtherWeeks() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = FocusStore(context: container.mainContext)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day, endedAt: Self.day,
                         focusedSeconds: 1200, blocksCompleted: 1, projectTaskID: nil)
        try store.record(mood: "sleep", source: "soundscape", startedAt: Self.day, endedAt: Self.day,
                         focusedSeconds: 3000, blocksCompleted: 0, projectTaskID: nil)
        try store.record(mood: "focus", source: "soundscape", startedAt: Self.day.addingTimeInterval(-14 * 86_400),
                         endedAt: Self.day.addingTimeInterval(-14 * 86_400), focusedSeconds: 900, blocksCompleted: 1, projectTaskID: nil)
        #expect(try store.focusedSeconds(inWeekOf: Self.day, calendar: Self.utc) == 1200)
    }
}
