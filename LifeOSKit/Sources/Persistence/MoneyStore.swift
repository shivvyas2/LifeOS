import Foundation
import SwiftData

@MainActor
public struct MoneyStore {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Transactions in a date range, most-recent-first. Always bounded.
    public func entries(from start: Date, to end: Date) throws -> [MoneyEntry] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.startOfDay(for: end)
        return try context.fetch(
            FetchDescriptor<MoneyEntry>(
                predicate: #Predicate { $0.date >= lower && $0.date <= upper },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    /// The calendar month containing `date`.
    public func monthEntries(containing date: Date = .now) throws -> [MoneyEntry] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        return try entries(from: interval.start, to: date)
    }

    public func accounts() throws -> [MoneyAccount] {
        try context.fetch(FetchDescriptor<MoneyAccount>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    public func add(
        date: Date,
        amount: Double,
        merchant: String,
        category: String? = nil,
        source: MoneySource = .manual,
        externalID: String? = nil
    ) throws -> MoneyEntry {
        let entry = MoneyEntry(
            date: calendar.startOfDay(for: date),
            amount: amount,
            merchant: merchant,
            category: category,
            source: source,
            externalID: externalID
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    public func delete(_ entry: MoneyEntry) throws {
        context.delete(entry)
        try context.save()
    }

    /// Upsert keyed on Plaid's `transaction_id`, so a re-sync corrects a
    /// settled transaction instead of adding a duplicate alongside the pending
    /// one. Batched: one save for the whole page.
    public func ingest(_ incoming: [(externalID: String, date: Date, amount: Double,
                                     merchant: String, category: String?, pending: Bool)]) throws {
        for row in incoming {
            let id = row.externalID
            let existing = try context.fetch(
                FetchDescriptor<MoneyEntry>(predicate: #Predicate { $0.externalID == id })
            ).first

            let entry = existing ?? MoneyEntry(
                date: row.date, amount: row.amount, merchant: row.merchant,
                source: .plaid, externalID: row.externalID
            )
            if existing == nil { context.insert(entry) }

            entry.date = calendar.startOfDay(for: row.date)
            entry.amount = row.amount
            entry.merchant = row.merchant
            entry.category = row.category
            entry.pending = row.pending
            entry.updatedAt = .now
        }
        try context.save()
    }
}
