import Foundation
import SwiftData

/// One incoming transaction, in this app's vocabulary rather than a provider's.
///
/// `Persistence` deliberately does not name Plaid. The mapping from a provider
/// payload to these fields, including the sign flip, belongs to `Integrations`.
///
/// The neutrality stops at `source`, which `ingest` records as `.plaid` because
/// bulk sync has exactly one provider today. A second one would need a `source`
/// on this struct; that field is left off until something actually needs it.
public struct MoneyIngestRow: Sendable, Equatable {
    public let externalID: String
    public let date: Date
    /// Positive is money in. Already negated by the caller if it was an outflow.
    public let amount: Double
    public let merchant: String
    public let category: String?
    public let categoryCode: String?
    public let merchantID: String?
    public let pending: Bool
    public let accountID: String?
    public let accountName: String?
    public let currencyCode: String

    public init(externalID: String, date: Date, amount: Double, merchant: String,
                category: String?, categoryCode: String?, merchantID: String?, pending: Bool,
                accountID: String?, accountName: String?, currencyCode: String) {
        self.externalID = externalID
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.categoryCode = categoryCode
        self.merchantID = merchantID
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
    /// checking, savings, credit card, mortgage. See MoneyAccount.subtype.
    public let subtype: String?
    public let mask: String?
    public let currentBalance: Double
    public let availableBalance: Double?
    /// Nil where the institution does not report one. Never zero. See
    /// MoneyAccount.creditLimit.
    public let creditLimit: Double?
    public let currencyCode: String

    public init(externalID: String, name: String, type: String,
                subtype: String?, mask: String?,
                currentBalance: Double, availableBalance: Double?,
                creditLimit: Double?, currencyCode: String) {
        self.externalID = externalID
        self.name = name
        self.type = type
        self.subtype = subtype
        self.mask = mask
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.creditLimit = creditLimit
        self.currencyCode = currencyCode
    }
}

/// The write side of the store, as a protocol, so a sync runner can be tested
/// against a store that fails on demand. Failure is the interesting case: the
/// cursor must not move when the ingest did not happen.
@MainActor public protocol MoneyIngesting {
    func ingest(_ incoming: [MoneyIngestRow]) throws
    func remove(externalIDs: [String]) throws
    func upsertAccounts(_ incoming: [MoneyAccountRow]) throws
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
    ///
    /// `externalID` has no index, and this runs on the main actor, so a
    /// per-row fetch inside the loop is an unindexed table scan per row: an
    /// initial multi-year pull is thousands of rows, all blocking the main
    /// thread. Fetching every id this page touches once, up front, turns that
    /// into a single scan; the dictionary is kept up to date as rows are
    /// inserted so a duplicate id within the same page still upserts instead
    /// of creating a second row.
    public func ingest(_ incoming: [MoneyIngestRow]) throws {
        let ids: Set<String?> = Set(incoming.map { $0.externalID as String? })
        var byExternalID = try context.fetch(
            FetchDescriptor<MoneyEntry>(predicate: #Predicate<MoneyEntry> { ids.contains($0.externalID) })
        ).reduce(into: [String: MoneyEntry]()) { result, entry in
            if let id = entry.externalID { result[id] = entry }
        }

        for row in incoming {
            let id = row.externalID
            let existing = byExternalID[id]

            let entry = existing ?? MoneyEntry(
                date: row.date, amount: row.amount, merchant: row.merchant,
                source: .plaid, externalID: row.externalID
            )
            if existing == nil {
                context.insert(entry)
                byExternalID[id] = entry
            }

            entry.date = calendar.startOfDay(for: row.date)
            entry.amount = row.amount
            entry.merchant = row.merchant
            entry.category = row.category
            entry.categoryCode = row.categoryCode
            entry.merchantID = row.merchantID
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
    ///
    /// One fetch for the whole batch rather than one per id, for the same
    /// reason as `ingest`: `externalID` is unindexed and this is main-actor work.
    public func remove(externalIDs: [String]) throws {
        guard !externalIDs.isEmpty else { return }
        let ids: Set<String?> = Set(externalIDs.map { $0 as String? })
        let matches = try context.fetch(
            FetchDescriptor<MoneyEntry>(predicate: #Predicate<MoneyEntry> { ids.contains($0.externalID) })
        )
        for match in matches { context.delete(match) }
        try context.save()
    }

    /// Upsert keyed on the provider's account id, so a balance moves rather
    /// than a second copy of the account appearing and doubling net worth.
    /// Batched the same way as `ingest`, for the same reason.
    public func upsertAccounts(_ incoming: [MoneyAccountRow]) throws {
        let ids: Set<String?> = Set(incoming.map { $0.externalID as String? })
        var byExternalID = try context.fetch(
            FetchDescriptor<MoneyAccount>(predicate: #Predicate<MoneyAccount> { ids.contains($0.externalID) })
        ).reduce(into: [String: MoneyAccount]()) { result, account in
            if let id = account.externalID { result[id] = account }
        }

        for row in incoming {
            let id = row.externalID
            let existing = byExternalID[id]

            let account = existing ?? MoneyAccount(
                name: row.name, type: row.type, currentBalance: row.currentBalance,
                currencyCode: row.currencyCode, externalID: row.externalID
            )
            if existing == nil {
                context.insert(account)
                byExternalID[id] = account
            }

            account.name = row.name
            account.type = row.type
            account.subtype = row.subtype
            account.mask = row.mask
            account.availableBalance = row.availableBalance
            account.creditLimit = row.creditLimit
            account.currentBalance = row.currentBalance
            account.currencyCode = row.currencyCode
            account.updatedAt = .now
        }
        try context.save()
    }

    // MARK: - Spend buckets

    public func buckets() throws -> [SpendBucket] {
        try context.fetch(
            FetchDescriptor<SpendBucket>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
            )
        )
    }

    @discardableResult
    public func addBucket(name: String, monthlyLimit: Double) throws -> SpendBucket {
        guard monthlyLimit > 0 else { throw SpendBucketError.limitNotPositive }
        let bucket = SpendBucket(
            name: name,
            monthlyLimit: monthlyLimit,
            sortOrder: (try buckets().last?.sortOrder ?? -1) + 1
        )
        context.insert(bucket)
        try context.save()
        return bucket
    }

    public func updateBucket(_ bucket: SpendBucket, name: String, monthlyLimit: Double) throws {
        guard monthlyLimit > 0 else { throw SpendBucketError.limitNotPositive }
        bucket.name = name
        bucket.monthlyLimit = monthlyLimit
        bucket.updatedAt = .now
        try context.save()
    }

    public func deleteBucket(_ bucket: SpendBucket) throws {
        context.delete(bucket)
        try context.save()
    }

    /// Claims `key` for `bucket`. A key another bucket holds moves rather
    /// than being held twice, and the previous holder's name comes back so
    /// the UI can say so.
    @discardableResult
    public func claim(_ key: String, for bucket: SpendBucket) throws -> String? {
        var movedFrom: String?
        for other in try buckets() where other.id != bucket.id {
            if let index = other.claimedRaw.firstIndex(of: key) {
                other.claimedRaw.remove(at: index)
                other.updatedAt = .now
                movedFrom = other.name
            }
        }
        if !bucket.claimedRaw.contains(key) {
            bucket.claimedRaw.append(key)
            bucket.updatedAt = .now
        }
        try context.save()
        return movedFrom
    }

    public func unclaim(_ key: String, from bucket: SpendBucket) throws {
        bucket.claimedRaw.removeAll { $0 == key }
        bucket.updatedAt = .now
        try context.save()
    }
}

extension MoneyStore: MoneyIngesting {}
