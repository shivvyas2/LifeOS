import Foundation
import SwiftData
import Persistence
import Sectors

@MainActor @Observable
final class MoneyViewModel {
    private(set) var snapshot = MoneySnapshot()
    private(set) var buckets: [SpendBucket] = []

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Shared with the Settings toggle that writes it. Delete alongside
    /// `SampleMoneyData.swift` when Plaid lands.
    static let sampleDataKey = "useSampleFinanceData"

    func attach(_ context: ModelContext) {
        self.context = context
    }

    func load(connection: PlaidConnectionViewModel? = nil) {
        // Off unless deliberately switched on in Settings. This now applies in
        // release builds too, so that a TestFlight tester can see the screen
        // while bank connection is broken. The snapshot it returns carries
        // `isSample`, and the screen says so on itself: nothing here may look
        // like the reader's real money.
        if UserDefaults.standard.bool(forKey: Self.sampleDataKey) {
            snapshot = .sample
            return
        }
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)

        do {
            let entries = try store.monthEntries()
            let accounts = try store.accounts()
            let summary = summarise(entries: entries, accounts: accounts)

            buckets = try store.buckets()
            var budgetRows: [BudgetBandRow] = []
            var unclaimedRows: [UnclaimedBandRow] = []
            if !buckets.isEmpty {
                let budget = BudgetPeriod.assess(
                    buckets: buckets.map(BudgetBucket.init),
                    lines: BudgetPeriod.lines(from: entries)
                )
                budgetRows = budget.rows.map {
                    BudgetBandRow(id: $0.id, name: $0.name, limit: $0.limit, spent: $0.spent)
                }
                unclaimedRows = budget.unclaimed.map {
                    UnclaimedBandRow(
                        id: $0.key ?? "uncategorised",
                        label: $0.label ?? $0.key ?? "Uncategorised",
                        amount: $0.amount,
                        count: $0.count
                    )
                }
            }

            let bankNames: [String]
            var reconnect: String?
            switch connection?.state {
            case .connected(let names): bankNames = names
            case .needsReconnect(let name): bankNames = [name]; reconnect = name
            default: bankNames = []
            }

            snapshot = MoneySnapshot(
                income: summary.income,
                expenses: summary.expenses,
                net: summary.net,
                savingsRate: summary.savingsRate,
                netWorth: summary.netWorth,
                recent: entries.prefix(8).map {
                    MoneyRow(id: $0.id, merchant: $0.merchant, category: $0.category,
                             amount: $0.amount, date: $0.date, pending: $0.pending)
                },
                budgets: budgetRows,
                unclaimed: unclaimedRows,
                monthLabel: Date.now.formatted(.dateTime.month(.wide).year()),
                // A bank linked seconds ago has no transactions yet. Falling back
                // to the empty state there tells the user the connection failed
                // when it did not.
                isConnected: !entries.isEmpty || !accounts.isEmpty || !bankNames.isEmpty,
                hasConnectedBank: !bankNames.isEmpty,
                isFetchingHistory: connection?.isFetchingHistory ?? false,
                reconnectPrompt: reconnect,
                lastSyncedAt: connection?.lastSyncedAt
            )
        } catch {
            assertionFailure("Money load failed: \(error)")
        }
    }

    /// Manual entry until Plaid is wired. `isIncome` decides the sign here so
    /// the rest of the app never has to guess at a bare number's direction.
    func add(merchant: String, amount: Double, isIncome: Bool, category: String?) {
        guard let context, !merchant.isEmpty, amount > 0 else { return }
        do {
            try MoneyStore(context: context, calendar: calendar).add(
                date: .now,
                amount: isIncome ? amount : -amount,
                merchant: merchant,
                category: category
            )
            load()
        } catch {
            assertionFailure("Money add failed: \(error)")
        }
    }

    // MARK: - Bucket editing

    /// Everything claimable: keys seen on the last three months of entries
    /// plus keys buckets already hold, each with the display label the
    /// transaction list uses and the name of the bucket holding it, if any.
    /// Three months, not one: the category you spent in last month but not
    /// yet this month is exactly the one you are budgeting for.
    func claimableCategories() -> [ClaimableCategory] {
        guard let context else { return [] }
        let store = MoneyStore(context: context, calendar: calendar)

        var labelByKey: [String: String] = [:]
        var order: [String] = []
        let start = calendar.date(byAdding: .month, value: -3, to: .now) ?? .now
        for entry in (try? store.entries(from: start, to: .now)) ?? [] {
            guard let key = entry.claimKey else { continue }
            if labelByKey[key] == nil { order.append(key) }
            labelByKey[key] = entry.category ?? key
        }
        for bucket in buckets {
            for key in bucket.claimedRaw where labelByKey[key] == nil {
                order.append(key)
                labelByKey[key] = key
            }
        }

        let holderByKey = buckets.reduce(into: [String: String]()) { result, bucket in
            for key in bucket.claimedRaw { result[key] = bucket.name }
        }
        return order.sorted { labelByKey[$0]! < labelByKey[$1]! }.map {
            ClaimableCategory(id: $0, label: labelByKey[$0]!, holder: holderByKey[$0])
        }
    }

    /// Creates or updates a bucket, then reconciles its claims. The store
    /// owns the single-holder rule; a key claimed here moves from whichever
    /// bucket held it.
    func saveBucket(id: UUID?, name: String, limit: Double, claimed: Set<String>) {
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)
        do {
            let bucket: SpendBucket
            if let id, let existing = buckets.first(where: { $0.id == id }) {
                try store.updateBucket(existing, name: name, monthlyLimit: limit)
                bucket = existing
            } else {
                bucket = try store.addBucket(name: name, monthlyLimit: limit)
            }
            for key in Set(bucket.claimedRaw).subtracting(claimed) {
                try store.unclaim(key, from: bucket)
            }
            for key in claimed.subtracting(bucket.claimedRaw) {
                try store.claim(key, for: bucket)
            }
            load()
        } catch {
            assertionFailure("Bucket save failed: \(error)")
        }
    }

    func deleteBucket(id: UUID) {
        guard let context, let bucket = buckets.first(where: { $0.id == id }) else { return }
        do {
            try MoneyStore(context: context, calendar: calendar).deleteBucket(bucket)
            load()
        } catch {
            assertionFailure("Bucket delete failed: \(error)")
        }
    }
}

struct ClaimableCategory: Equatable, Identifiable {
    /// The claim key.
    let id: String
    let label: String
    /// Name of the bucket holding this key, nil when it is free.
    let holder: String?
}
