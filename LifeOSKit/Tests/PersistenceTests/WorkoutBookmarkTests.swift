import Foundation
import SwiftData
import Testing
@testable import Persistence

struct WorkoutBookmarkTests {
    @Test @MainActor func togglingSavedTwiceLeavesNoRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = container.mainContext

        let firstToggle = try BookmarkStore.toggleSaved("vid1", context: context)
        #expect(firstToggle == true)
        #expect(try BookmarkStore.bookmark(for: "vid1", context: context)?.saved == true)

        let secondToggle = try BookmarkStore.toggleSaved("vid1", context: context)
        #expect(secondToggle == false)
        #expect(try BookmarkStore.bookmark(for: "vid1", context: context) == nil)
        #expect(try BookmarkStore.all(context: context).isEmpty)
    }

    @Test @MainActor func schedulingNormalisesToDayStartAndIsFoundByDay() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 14; components.hour = 19; components.minute = 30
        let eveningTime = try #require(calendar.date(from: components))

        try BookmarkStore.schedule("vid2", on: eveningTime, context: context, calendar: calendar)

        let dayStart = calendar.startOfDay(for: eveningTime)
        let stored = try #require(try BookmarkStore.bookmark(for: "vid2", context: context))
        #expect(stored.scheduledFor == dayStart)

        let found = try BookmarkStore.scheduled(on: eveningTime, context: context, calendar: calendar)
        #expect(found.map(\.youtubeID) == ["vid2"])
    }

    @Test @MainActor func clearingScheduleOnASavedRowKeepsTheRow() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)

        _ = try BookmarkStore.toggleSaved("vid3", context: context)
        try BookmarkStore.schedule("vid3", on: .now, context: context, calendar: calendar)
        #expect(try BookmarkStore.bookmark(for: "vid3", context: context)?.scheduledFor != nil)

        try BookmarkStore.schedule("vid3", on: nil, context: context, calendar: calendar)
        let stored = try #require(try BookmarkStore.bookmark(for: "vid3", context: context))
        #expect(stored.saved == true)
        #expect(stored.scheduledFor == nil)
    }

    @Test @MainActor func clearingScheduleOnAnUnsavedRowDeletesIt() throws {
        let container = try LifeOSContainer.make(inMemory: true)
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)

        try BookmarkStore.schedule("vid4", on: .now, context: context, calendar: calendar)
        #expect(try BookmarkStore.bookmark(for: "vid4", context: context) != nil)

        try BookmarkStore.schedule("vid4", on: nil, context: context, calendar: calendar)
        #expect(try BookmarkStore.bookmark(for: "vid4", context: context) == nil)
        #expect(try BookmarkStore.all(context: context).isEmpty)
    }
}
