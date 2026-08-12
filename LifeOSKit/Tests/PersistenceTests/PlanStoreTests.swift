import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct PlanStoreTests {
    private func makeStore() throws -> PlanStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return PlanStore(context: ModelContext(container))
    }

    @Test func togglingAHabitIsIdempotentPerDay() throws {
        let store = try makeStore()
        let habit = try store.add(kind: .habit, title: "Meditate")

        #expect(try store.toggleTick(for: habit) == true)
        #expect(try store.toggleTick(for: habit) == false)
        #expect(try store.recentTicks(for: habit, days: 1).allSatisfy { $0 == false })
    }

    @Test func recentTicksAreOldestFirstAndSpanTheWindow() throws {
        let store = try makeStore()
        let habit = try store.add(kind: .habit, title: "Read")
        let calendar = Calendar.current
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: .now)!

        try store.toggleTick(for: habit, on: twoDaysAgo)

        let ticks = try store.recentTicks(for: habit, days: 3)
        #expect(ticks.count == 3)
        #expect(ticks == [true, false, false])
    }

    /// An unticked today must not read as a broken streak: the day is not over.
    @Test func anOpenTodayDoesNotBreakTheStreak() throws {
        let store = try makeStore()
        let habit = try store.add(kind: .habit, title: "Walk")
        let calendar = Calendar.current

        for offset in [1, 2, 3] {
            try store.toggleTick(for: habit, on: calendar.date(byAdding: .day, value: -offset, to: .now)!)
        }
        #expect(try store.streak(for: habit) == 3)
    }

    @Test func deletingAHabitRemovesItsTicks() throws {
        let store = try makeStore()
        let habit = try store.add(kind: .habit, title: "Stretch")
        try store.toggleTick(for: habit)
        try store.delete(habit)

        #expect(try store.entries(kind: .habit).isEmpty)
    }

    @Test func entriesAreScopedToTheirKind() throws {
        let store = try makeStore()
        try store.add(kind: .goal, title: "Ship the first release", progressValue: 3, progressTarget: 4)
        try store.add(kind: .note, title: "Client X notes")

        #expect(try store.entries(kind: .goal).count == 1)
        #expect(try store.entries(kind: .note).count == 1)
        #expect(try store.entries(kind: .habit).isEmpty)
    }

    @Test func goalFractionComesFromMilestones() throws {
        let store = try makeStore()
        let goal = try store.add(kind: .goal, title: "Savings", progressValue: 6_000, progressTarget: 10_000)
        #expect(goal.snapshot().fraction == 0.6)
    }

    // MARK: - tickedHabitIDs tests

    /// Fixed to UTC so the day-boundary test means the same thing everywhere.
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Day-boundary tests must work against a fixed timezone, not the system's.
    /// The main factory uses Calendar.current for backward compatibility with
    /// existing tests that rely on relative dates like "two days ago."
    private func makeUTCStore() throws -> PlanStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return PlanStore(context: ModelContext(container), calendar: utcCalendar)
    }

    private var day: Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
    }

    private var nextDay: Date {
        utcCalendar.date(byAdding: .day, value: 1, to: day)!
    }

    @Test func returnsOnlyTheHabitsTickedOnThatDay() throws {
        let store = try makeUTCStore()
        let read = try store.add(kind: .habit, title: "Read")
        let gym = try store.add(kind: .habit, title: "Gym")
        _ = try store.add(kind: .habit, title: "Water")   // exists, never ticked

        try store.toggleTick(for: read, on: day)
        try store.toggleTick(for: gym, on: day)

        #expect(try store.tickedHabitIDs(on: day) == Set([read.id, gym.id]))
    }

    @Test func isEmptyForADayWithNoTicks() throws {
        let store = try makeUTCStore()
        let read = try store.add(kind: .habit, title: "Read")
        try store.toggleTick(for: read, on: day)

        #expect(try store.tickedHabitIDs(on: nextDay).isEmpty)
    }

    /// The `startOfDay` boundary. A tick logged just before midnight belongs to
    /// the day it was logged on, not to the one starting a minute later.
    @Test func aTickLateInTheEveningBelongsToThatDay() throws {
        let store = try makeUTCStore()
        let read = try store.add(kind: .habit, title: "Read")
        let lateEvening = day.addingTimeInterval(23 * 3600 + 59 * 60)

        try store.toggleTick(for: read, on: lateEvening)

        #expect(try store.tickedHabitIDs(on: day) == Set([read.id]))
        #expect(try store.tickedHabitIDs(on: nextDay).isEmpty)
    }

    /// Un-ticking must actually remove the id, not just flip a flag somewhere.
    @Test func unTickingRemovesTheHabitFromTheDay() throws {
        let store = try makeUTCStore()
        let read = try store.add(kind: .habit, title: "Read")

        try store.toggleTick(for: read, on: day)
        try store.toggleTick(for: read, on: day)

        #expect(try store.tickedHabitIDs(on: day).isEmpty)
    }
}
