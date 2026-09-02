import Foundation
import SwiftData
import Persistence
import Sectors
import Insights

@MainActor @Observable
final class MoneyViewModel {
    private(set) var snapshot = MoneySnapshot()
    private(set) var buckets: [SpendBucket] = []

    private var context: ModelContext?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    /// Real rows only. The invented sample month that used to stand in
    /// before a bank was connected is gone: every figure on the Money tab is
    /// now something that happened.
    func load(connection: PlaidConnectionViewModel? = nil) {
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

            let logos = Self.logoMap(from: entries)
            let rows = Self.rows(from: entries, logos: logos)
            let categories = Self.categories(from: entries, expenses: summary.expenses)

            snapshot = MoneySnapshot(
                income: summary.income,
                expenses: summary.expenses,
                net: summary.net,
                savingsRate: summary.savingsRate,
                netWorth: summary.netWorth,
                recent: rows,
                budgets: budgetRows,
                unclaimed: unclaimedRows,
                categories: categories,
                recurring: Self.recurring(from: entries, calendar: calendar, logos: logos),
                week: Self.week(from: entries, now: .now, calendar: calendar),
                slices: Self.slices(from: categories),
                spendCount: entries.filter(\.isSpending).count,
                goal: Self.goal(saved: summary.net),
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

    // MARK: - Derived views of the month

    /// Spending grouped by category, largest first.
    ///
    /// Built from `isSpending` only, the same predicate as `summarise`, so
    /// the list sums to the "Spent" figure above it. Uncategorised spend is
    /// kept rather than dropped for the same reason: the gap is exactly the
    /// spend nobody has labelled.
    static func categories(from entries: [MoneyEntry], expenses: Double) -> [CategoryRow] {
        guard expenses > 0 else { return [] }
        let grouped = Dictionary(grouping: entries.filter(\.isSpending)) { $0.category ?? "Uncategorised" }

        return grouped.map { name, rows in
            let amount = rows.reduce(0) { $0 + abs($1.amount) }
            return CategoryRow(id: name, name: name, amount: amount,
                               share: amount / expenses, count: rows.count)
        }
        .sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }
    }

    /// Merchants billing every month, detected from history by `RecurringSpend`.
    static func recurring(from entries: [MoneyEntry], calendar: Calendar,
                          logos: [String: URL] = [:]) -> [RecurringRow] {
        let lines = entries.map {
            RecurringSpend.Line(merchant: $0.merchant, category: $0.category,
                                amount: $0.amount, date: $0.date)
        }
        return RecurringSpend.charges(in: lines, calendar: calendar).map {
            RecurringRow(id: $0.merchant, merchant: $0.merchant, category: $0.category,
                         amount: $0.typicalAmount, months: $0.months,
                         logoURL: logos[Self.logoKey(merchant: $0.merchant)])
        }
    }

    /// Every logo in the window, keyed twice: by merchant entity where Plaid
    /// gave one, and by lowercased merchant name always. A row Plaid sent
    /// without a logo borrows from any sibling that has one; a manual "Netflix"
    /// picks up the mark from the Plaid rows. A borrowed logo never changes
    /// grouping: it is a picture beside a name, not an identity.
    static func logoMap(from entries: [MoneyEntry]) -> [String: URL] {
        var map: [String: URL] = [:]
        for entry in entries {
            guard let raw = entry.logoURL, let url = URL(string: raw) else { continue }
            if let id = entry.merchantID { map["id:\(id)"] = map["id:\(id)"] ?? url }
            let key = Self.logoKey(merchant: entry.merchant)
            map[key] = map[key] ?? url
        }
        return map
    }

    static func logoKey(merchant: String) -> String {
        "name:" + merchant.lowercased().trimmingCharacters(in: .whitespaces)
    }

    static func logo(for entry: MoneyEntry, in logos: [String: URL]) -> URL? {
        if let raw = entry.logoURL, let url = URL(string: raw) { return url }
        if let id = entry.merchantID, let url = logos["id:\(id)"] { return url }
        return logos[Self.logoKey(merchant: entry.merchant)]
    }

    static func rows(from entries: [MoneyEntry], logos: [String: URL]) -> [MoneyRow] {
        entries.map {
            MoneyRow(id: $0.id, merchant: $0.merchant, category: $0.category,
                     amount: $0.amount, date: $0.date, pending: $0.pending,
                     logoURL: Self.logo(for: $0, in: logos), accountName: $0.accountName)
        }
    }

    /// The week from the month's own entries. A week that begins in the
    /// previous month reads zero for those days; the tab loads one month,
    /// and a straddling week is six days a year.
    static func week(from entries: [MoneyEntry], now: Date, calendar: Calendar) -> [DaySpend] {
        let today = calendar.startOfDay(for: now)
        let lines = entries.filter(\.isSpending).map { SpendSeries.Line(amount: $0.amount, date: $0.date) }
        return SpendSeries.week(of: now, lines: lines, calendar: calendar).map {
            DaySpend(date: $0.date, amount: $0.amount, isFuture: $0.isFuture,
                     isToday: calendar.isDate($0.date, inSameDayAs: today))
        }
    }

    /// The donut: five largest categories and an "Other", each with its ink
    /// step. Shares are of the full month, so the slices still sum to one.
    static func slices(from categories: [CategoryRow]) -> [CategorySlice] {
        let total = categories.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        let folded = SpendSeries.fold(
            categories.map { SpendSeries.Share(name: $0.name, amount: $0.amount) }, keep: 5
        )
        return folded.enumerated().map { index, share in
            CategorySlice(id: share.name, name: share.name, amount: share.amount,
                          share: share.amount / total,
                          opacity: CategorySlice.steps[min(index, CategorySlice.steps.count - 1)],
                          isOther: share.name == "Other" && !categories.contains { $0.name == "Other" })
        }
    }

    /// The saving target, when one has been named.
    ///
    /// Progress is this month's net rather than a running balance: the app has
    /// no account history to total, and claiming a lifetime figure it cannot
    /// see would be inventing one. A month that kept nothing shows zero saved,
    /// which is the honest reading.
    static func goal(saved: Double) -> SavingsGoal? {
        let defaults = UserDefaults.standard
        let target = defaults.double(forKey: goalTargetKey)
        guard target > 0 else { return nil }
        let name = defaults.string(forKey: goalNameKey) ?? "Savings goal"
        return SavingsGoal(name: name, target: target, saved: max(saved, 0))
    }

    static let goalTargetKey = "savingsGoalTarget"
    static let goalNameKey = "savingsGoalName"
}

struct ClaimableCategory: Equatable, Identifiable {
    /// The claim key.
    let id: String
    let label: String
    /// Name of the bucket holding this key, nil when it is free.
    let holder: String?
}
