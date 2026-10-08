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

            let resolver = try store.cardResolver()
            let cardIndex = Self.cardIndex(accounts: accounts)
            let logos = Self.logoMap(from: entries)
            let rows = Self.rows(from: entries, logos: logos, resolver: resolver, cards: cardIndex)
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
                lastSyncedAt: connection?.lastSyncedAt,
                cards: Self.strip(accounts: accounts, entries: entries, resolver: resolver),
                pickableCards: Self.pickable(accounts: accounts)
            )
        } catch {
            assertionFailure("Money load failed: \(error)")
        }
    }

    /// Manual entry, for cash and for cards Plaid cannot see. `isIncome`
    /// decides the sign here so the rest of the app never has to guess at a
    /// bare number's direction.
    func add(merchant: String, amount: Double, isIncome: Bool, category: String?,
             cardKey: String? = nil, connection: PlaidConnectionViewModel? = nil) {
        guard let context, !merchant.isEmpty, amount > 0 else { return }
        do {
            try MoneyStore(context: context, calendar: calendar).add(
                date: .now,
                amount: isIncome ? amount : -amount,
                merchant: merchant,
                category: category,
                cardKey: cardKey
            )
            if let cardKey { lastCardKey = cardKey }
            load(connection: connection)
        } catch {
            assertionFailure("Money add failed: \(error)")
        }
    }

    // MARK: - Cards

    /// The card quick add starts on: whichever was used last, while it still
    /// exists.
    var lastCardKey: String? {
        get {
            let key = UserDefaults.currentAccount.string(forKey: Self.lastCardKeyKey)
            return snapshot.pickableCards.contains { $0.id == key } ? key : nil
        }
        set { UserDefaults.currentAccount.set(newValue, forKey: Self.lastCardKeyKey) }
    }

    static let lastCardKeyKey = "money.lastCardKey"

    /// Says which card paid for one row, and optionally for every row from
    /// that merchant. Nil clears the row's choice and drops the merchant's
    /// rule, so "No card" really means Plaid's word stands.
    func setCard(_ cardKey: String?, for row: MoneyRow, always: Bool,
                 connection: PlaidConnectionViewModel? = nil) {
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)
        do {
            guard let entry = try store.entry(id: row.id) else { return }
            if always, let cardKey {
                try store.setCardRule(merchant: row.merchant, cardKey: cardKey)
                // The rule speaks for this row now; a stale choice on it
                // would otherwise outrank the rule just made.
                try store.setCard(nil, for: entry)
            } else {
                if cardKey == nil { try store.removeCardRule(merchant: row.merchant) }
                try store.setCard(cardKey, for: entry)
            }
            if let cardKey { lastCardKey = cardKey }
            load(connection: connection)
        } catch {
            assertionFailure("Card choice failed: \(error)")
        }
    }

    /// Whether the merchant on this row already has an "always" rule.
    func hasCardRule(for merchant: String) -> Bool {
        guard let context else { return false }
        let key = CardResolver.merchantKey(merchant)
        return ((try? MoneyStore(context: context).cardRules()) ?? []).contains { $0.merchantKey == key }
    }

    /// Adds a hand-added card or restyles an existing one.
    func saveCard(_ draft: CardDraft, connection: PlaidConnectionViewModel? = nil) {
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)
        do {
            if let key = draft.existingKey,
               let account = try store.accounts().first(where: { $0.cardKey == key }) {
                try store.updateCard(account, name: draft.name, productID: draft.productID,
                                     mask: draft.mask, colorHex: draft.colorHex)
            } else {
                let card = try store.addManualCard(name: draft.name, productID: draft.productID,
                                                   mask: draft.mask, colorHex: draft.colorHex)
                lastCardKey = card.cardKey
            }
            load(connection: connection)
        } catch {
            assertionFailure("Card save failed: \(error)")
        }
    }

    func deleteCard(key: String, connection: PlaidConnectionViewModel? = nil) {
        guard let context else { return }
        let store = MoneyStore(context: context, calendar: calendar)
        do {
            guard let account = try store.accounts().first(where: { $0.cardKey == key }) else { return }
            try store.deleteManualCard(account)
            load(connection: connection)
        } catch {
            assertionFailure("Card delete failed: \(error)")
        }
    }

    /// Which of a statement's rows already look like something in the app,
    /// from the same card or none, in the statement's own date range.
    func duplicates(in lines: [StatementLine], cardKey: String) -> Set<UUID> {
        guard let context, let first = lines.map(\.date).min(), let last = lines.map(\.date).max() else { return [] }
        let store = MoneyStore(context: context, calendar: calendar)
        let window = TimeInterval(StatementDedupe.windowDays * 86_400)
        guard let resolver = try? store.cardResolver(),
              let nearby = try? store.entries(from: first.addingTimeInterval(-window),
                                              to: last.addingTimeInterval(window))
        else { return [] }
        // A row on another card is a different purchase, even at the same
        // price. A row with no card at all might be this one.
        let candidates = nearby.filter {
            let key = resolver.cardKey(for: $0)
            return key == nil || key == cardKey
        }
        return StatementDedupe.duplicates(lines, existing: candidates, calendar: calendar)
    }

    func importStatement(_ lines: [StatementLine], cardKey: String,
                         connection: PlaidConnectionViewModel? = nil) {
        guard let context, !lines.isEmpty else { return }
        do {
            try MoneyStore(context: context, calendar: calendar).importStatement(lines, cardKey: cardKey)
            lastCardKey = cardKey
            load(connection: connection)
        } catch {
            assertionFailure("Statement import failed: \(error)")
        }
    }

    /// Every account by its card key, as the screens draw it.
    static func cardIndex(accounts: [MoneyAccount]) -> [String: MoneyCardSummary] {
        accounts.reduce(into: [:]) { $0[$1.cardKey] = MoneyCardSummary($1) }
    }

    /// The strip: every card, plus any other account that paid for something
    /// this month (a debit card spends from checking). Most spent first, so
    /// the card doing the damage is the first one you see.
    static func strip(accounts: [MoneyAccount], entries: [MoneyEntry],
                      resolver: CardResolver) -> [MoneyCardSummary] {
        var spend: [String: (Double, Int)] = [:]
        for entry in entries where entry.isSpending {
            guard let key = resolver.cardKey(for: entry) else { continue }
            let current = spend[key] ?? (0, 0)
            spend[key] = (current.0 + abs(entry.amount), current.1 + 1)
        }
        return accounts
            .filter { $0.isCard || spend[$0.cardKey] != nil }
            .map { account in
                var card = MoneyCardSummary(account)
                card.monthSpend = spend[card.id]?.0 ?? 0
                card.monthCount = spend[card.id]?.1 ?? 0
                return card
            }
            .sorted { ($0.monthSpend, $1.title) > ($1.monthSpend, $0.title) }
    }

    /// What a charge can be put on: cards first, then the bank accounts a
    /// debit card draws from. Investments and loans never pay for a coffee.
    static func pickable(accounts: [MoneyAccount]) -> [MoneyCardSummary] {
        accounts
            .filter { $0.isCard || $0.type == "depository" }
            .sorted { ($0.isCard ? 0 : 1, $0.name) < ($1.isCard ? 0 : 1, $1.name) }
            .map(MoneyCardSummary.init)
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

    static func rows(from entries: [MoneyEntry], logos: [String: URL],
                     resolver: CardResolver = CardResolver(),
                     cards: [String: MoneyCardSummary] = [:]) -> [MoneyRow] {
        entries.map {
            MoneyRow(id: $0.id, merchant: $0.merchant, category: $0.category,
                     amount: $0.amount, date: $0.date, pending: $0.pending,
                     logoURL: Self.logo(for: $0, in: logos), accountName: $0.accountName,
                     card: resolver.cardKey(for: $0).flatMap { cards[$0] })
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
        let defaults = UserDefaults.currentAccount
        let target = defaults.double(forKey: goalTargetKey)
        guard target > 0 else { return nil }
        let name = defaults.string(forKey: goalNameKey) ?? "Savings goal"
        return SavingsGoal(name: name, target: target, saved: max(saved, 0))
    }

    static let goalTargetKey = "savingsGoalTarget"
    static let goalNameKey = "savingsGoalName"
}

/// What the card editor hands back.
struct CardDraft: Equatable {
    /// The card being restyled, or nil for a new hand-added card.
    var existingKey: String?
    var name: String
    var productID: String?
    var mask: String?
    var colorHex: String?
}

struct ClaimableCategory: Equatable, Identifiable {
    /// The claim key.
    let id: String
    let label: String
    /// Name of the bucket holding this key, nil when it is free.
    let holder: String?
}
