import Foundation
import SwiftData

/// One incoming transaction, in this app's vocabulary rather than a provider's.
///
/// `Persistence` deliberately does not name Plaid. The mapping from a provider
/// payload to these fields, including the sign flip, belongs to `Integrations`,
/// so a second provider later is a new mapper and not a change down here.
public struct MoneyIngestRow: Sendable, Equatable {
    public let externalID: String
    public let date: Date
    /// Positive is money in. Already negated by the caller if it was an outflow.
    public let amount: Double
    public let merchant: String
    public let category: String?
    public let categoryCode: String?
    public let pending: Bool
    public let accountID: String?
    public let accountName: String?
    public let currencyCode: String

    public init(externalID: String, date: Date, amount: Double, merchant: String,
                category: String?, categoryCode: String?, pending: Bool,
                accountID: String?, accountName: String?, currencyCode: String) {
        self.externalID = externalID
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.categoryCode = categoryCode
        self.pending = pending
        self.accountID = accountID
        self.accountName = accountName
        self.currencyCode = currencyCode
    }
}

/// One funding account and its balance.
public struct MoneyAccountRow: Sendable, Equatable {
    public let externalID: String
    public let name: String
    /// depository, credit, investment or loan.
    public let type: String
    public let currentBalance: Double
    public let currencyCode: String

    public init(externalID: String, name: String, type: String,
                currentBalance: Double, currencyCode: String) {
        self.externalID = externalID
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.currencyCode = currencyCode
    }
}

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

    /// Upsert keyed on the provider's transaction id, so a re-sync corrects a
    /// settled transaction instead of adding a duplicate alongside the pending
    /// one. Batched: one save for the whole page.
    public func ingest(_ incoming: [MoneyIngestRow]) throws {
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
            entry.categoryCode = row.categoryCode
            entry.pending = row.pending
            entry.accountID = row.accountID
            entry.accountName = row.accountName
            entry.currencyCode = row.currencyCode
            entry.updatedAt = .now
        }
        try context.save()
    }

    /// Deletes by provider id. Silent about ids it does not hold: a replayed
    /// page can ask twice, and that is the ordinary cost of a device-owned
    /// cursor rather than a fault.
    public func remove(externalIDs: [String]) throws {
        guard !externalIDs.isEmpty else { return }
        for id in externalIDs {
            let matches = try context.fetch(
                FetchDescriptor<MoneyEntry>(predicate: #Predicate { $0.externalID == id })
            )
            for match in matches { context.delete(match) }
        }
        try context.save()
    }

    /// Upsert keyed on the provider's account id, so a balance moves rather
    /// than a second copy of the account appearing and doubling net worth.
    public func upsertAccounts(_ incoming: [MoneyAccountRow]) throws {
        for row in incoming {
            let id = row.externalID
            let existing = try context.fetch(
                FetchDescriptor<MoneyAccount>(predicate: #Predicate { $0.externalID == id })
            ).first

            let account = existing ?? MoneyAccount(
                name: row.name, type: row.type, currentBalance: row.currentBalance,
                currencyCode: row.currencyCode, externalID: row.externalID
            )
            if existing == nil { context.insert(account) }

            account.name = row.name
            account.type = row.type
            account.currentBalance = row.currentBalance
            account.currencyCode = row.currencyCode
            account.updatedAt = .now
        }
        try context.save()
    }
}
