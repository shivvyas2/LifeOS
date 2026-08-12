import Testing
import Foundation
import SwiftData
@testable import Persistence

@Suite @MainActor struct MoneyTests {
    private func makeStore() throws -> MoneyStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MoneyStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func summaryUsesOurSignConventionNotPlaids() {
        // Positive is money in. Plaid is the opposite and the ingestion layer
        // negates; if that ever regresses, income and expenses swap.
        let entries = [
            MoneyEntry(date: day, amount: 5_200, merchant: "Salary"),
            MoneyEntry(date: day, amount: -1_500, merchant: "Rent"),
            MoneyEntry(date: day, amount: -650, merchant: "Groceries"),
        ]
        let summary = summarise(entries: entries)

        #expect(summary.income == 5_200)
        #expect(summary.expenses == 2_150)
        #expect(summary.net == 3_050)
    }

    @Test func savingsRateIsUndefinedWithoutIncome() {
        // Not 0% but undefined. A savings rate against no income is a number this
        // app must not invent.
        let summary = summarise(entries: [MoneyEntry(date: day, amount: -40, merchant: "Coffee")])
        #expect(summary.savingsRate == nil)
        #expect(summary.income == 0)
    }

    @Test func pendingTransactionsAreExcludedFromTheRollup() {
        let settled = MoneyEntry(date: day, amount: -100, merchant: "Shop")
        let pending = MoneyEntry(date: day, amount: -999, merchant: "Hold", pending: true)
        let summary = summarise(entries: [settled, pending])
        #expect(summary.expenses == 100)
    }

    @Test func creditAndLoanBalancesSubtractFromNetWorth() {
        let accounts = [
            MoneyAccount(name: "Checking", type: "depository", currentBalance: 4_000),
            MoneyAccount(name: "Card", type: "credit", currentBalance: 1_200),
        ]
        let summary = summarise(entries: [], accounts: accounts)
        #expect(summary.netWorth == 2_800)
    }

    @Test func ingestUpdatesAPendingTransactionRatherThanDuplicatingIt() throws {
        let store = try makeStore()
        try store.ingest([(externalID: "txn_1", date: day, amount: -20,
                           merchant: "Cafe", category: nil, pending: true)])
        try store.ingest([(externalID: "txn_1", date: day, amount: -22.5,
                           merchant: "Cafe", category: "Food", pending: false)])

        let rows = try store.entries(from: day, to: day)
        #expect(rows.count == 1)
        #expect(rows[0].amount == -22.5)
        #expect(rows[0].pending == false)
    }
}

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
}
