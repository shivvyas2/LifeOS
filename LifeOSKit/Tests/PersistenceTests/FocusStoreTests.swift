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
}
