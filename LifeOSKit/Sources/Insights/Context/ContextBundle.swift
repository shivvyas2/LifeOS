import Foundation

/// Everything the coach may see about this user, assembled on the device per
/// request. The server uses it for one completion and discards it; nothing
/// here is ever stored remotely, which is the standing rule for user data
/// (see the plaid_items migration).
public struct ContextBundle: Sendable {

    public struct Money: Sendable, Equatable {
        public struct Transaction: Sendable, Equatable {
            public let merchant: String
            public let category: String?
            public let amount: Double
            public let date: Date

            public init(merchant: String, category: String?, amount: Double, date: Date) {
                self.merchant = merchant
                self.category = category
                self.amount = amount
                self.date = date
            }
        }

        public let income: Double
        public let expenses: Double
        public let savingsRate: Double?
        public let netWorth: Double?
        public let recent: [Transaction]

        public init(income: Double, expenses: Double, savingsRate: Double?,
                    netWorth: Double?, recent: [Transaction]) {
            self.income = income
            self.expenses = expenses
            self.savingsRate = savingsRate
            self.netWorth = netWorth
            self.recent = recent
        }

        public struct CategoryTotal: Sendable, Equatable {
            public let name: String
            /// Signed as the transactions are: spending is negative.
            public let total: Double
            public let count: Int
        }

        /// `recent` reduced to what may leave the device: spending summed per
        /// category, largest first. Income rows are excluded because the
        /// summary line already carries income. A category with a single
        /// purchase is a per-row amount under another name, so singletons
        /// fold into "Other"; and "Other" is itself dropped when it holds
        /// only one, because a lone leftover is still one row.
        public var spendingByCategory: [CategoryTotal] {
            let spending = recent.filter { $0.amount < 0 }
            let grouped = Dictionary(grouping: spending, by: { $0.category ?? "Other" })
            var other: [Transaction] = []
            var buckets: [CategoryTotal] = []
            for (name, rows) in grouped {
                if rows.count >= 2 && name != "Other" {
                    buckets.append(CategoryTotal(name: name, total: rows.reduce(0) { $0 + $1.amount },
                                                 count: rows.count))
                } else {
                    other.append(contentsOf: rows)
                }
            }
            if other.count >= 2 {
                buckets.append(CategoryTotal(name: "Other", total: other.reduce(0) { $0 + $1.amount },
                                             count: other.count))
            }
            return buckets.sorted { abs($0.total) != abs($1.total) ? abs($0.total) > abs($1.total) : $0.name < $1.name }
        }
    }

    public struct Sector: Sendable, Equatable {
        public let name: String
        public let score: Int?
        public let delta: Int?

        public init(name: String, score: Int?, delta: Int?) {
            self.name = name
            self.score = score
            self.delta = delta
        }
    }

    public let digest: MetricsDigest
    public let money: Money?
    public let sectors: [Sector]
    public let firstName: String?

    public init(digest: MetricsDigest, money: Money? = nil,
                sectors: [Sector] = [], firstName: String? = nil) {
        self.digest = digest
        self.money = money
        self.sectors = sectors
        self.firstName = firstName
    }

    /// Renders the bundle for one audience within a character budget. This is
    /// the prompt sent to a paid model on every off-device call, so `budget`
    /// is the thing that actually bounds what that call costs -- with one
    /// honest caveat: the render is bounded by `budget` plus, when the
    /// digest is non-empty, at most one irreducible day block.
    /// `MetricsDigest.promptLines(for:budget:)` keeps dropping days until
    /// what remains fits or only one day is left, and it always emits that
    /// last day even when it alone runs over budget. A digest that said
    /// nothing at all about the user's health would undermine the call more
    /// than one that ran slightly long, so that floor is a deliberate
    /// property of the digest, not a gap this type silently papers over.
    ///
    /// `.onDevice` keeps the render to the digest plus one sector line: the
    /// local window is small and a spending breakdown would push the health
    /// data out of it. `.offDevice` carries everything, apportioned so the
    /// whole render honours one budget rather than each section trusting its
    /// own: the user, sector, and money-summary lines are small, dense, and
    /// worth more per character than anything else here, so they are built
    /// first and never trimmed. The digest claims what is left of the budget
    /// next -- it already drops its oldest days first to fit whatever it is
    /// given, so handing it a smaller number just makes that existing
    /// truncation bite sooner. The spending breakdown gets only what neither
    /// of the above used, which is why it is the first thing to disappear
    /// under a tight budget.
    ///
    /// No audience ever sees a transaction row. `recent` exists so the
    /// breakdown can be computed on the device; what leaves the device is
    /// `Money.spendingByCategory`, a total and a count per category, never a
    /// merchant, a date, or a single amount. That is the privacy rule for a
    /// paid model: it may learn how spending splits, not who was paid when.
    public func promptLines(for audience: MetricsDigest.Audience, budget: Int = 8_000) -> String {
        let userLine = firstName.map { "User: \($0)" }

        let sectorLine: String? = sectors.isEmpty ? nil : {
            let scores = sectors.map { sector -> String in
                guard let score = sector.score else { return "\(sector.name) unscored" }
                let delta = sector.delta.map { $0 >= 0 ? " (+\($0))" : " (\($0))" } ?? ""
                return "\(sector.name) \(score)\(delta)"
            }
            return "Life sectors: " + scores.joined(separator: ", ")
        }()

        let moneyLine: String? = money.map { money in
            var line = "Money this month: income \(Int(money.income)), expenses \(Int(money.expenses))"
            if let rate = money.savingsRate { line += ", saved \(Int(rate * 100))%" }
            if let netWorth = money.netWorth { line += ", net worth \(Int(netWorth))" }
            return line
        }

        // These three survive any budget untouched, so they are reserved
        // before the digest sees a number; the digest gets whatever budget
        // is left, minus the separator that will join it to them.
        let summaryLines = [userLine, sectorLine, moneyLine].compactMap { $0 }
        let summaryText = summaryLines.joined(separator: "\n")
        let digestBudget = max(0, budget - summaryText.count - (summaryLines.isEmpty ? 0 : 1))
        let digestText = digest.promptLines(for: audience, budget: digestBudget)

        var blocks: [String] = []
        if let userLine { blocks.append(userLine) }
        // An empty digest (no days, no baseline) contributes nothing; append
        // it anyway and the render carries a stray blank line for no reason.
        if !digestText.isEmpty { blocks.append(digestText) }
        if let sectorLine { blocks.append(sectorLine) }
        if let moneyLine { blocks.append(moneyLine) }

        if let money, audience == .offDevice {
            // Every purchase, not just those a bucket accounts for, so the
            // model can tell when the breakdown is partial.
            let purchases = money.recent.filter { $0.amount < 0 }.count
            let header = "Spending by category (\(purchases) purchases):"
            // `spent` has to account for the header and the separator ahead
            // of it before the loop starts, not just the blocks built so
            // far -- otherwise every render that keeps at least one row
            // overshoots `budget` by exactly the header's length.
            var spent = blocks.joined(separator: "\n").count
                + (blocks.isEmpty ? 0 : 1) + header.count
            var rows: [String] = []
            for bucket in money.spendingByCategory {
                let row = "\(bucket.name) \(String(format: "%.2f", bucket.total)) (\(bucket.count))"
                guard spent + row.count + 1 <= budget else { break }
                rows.append(row)
                spent += row.count + 1
            }
            if !rows.isEmpty {
                blocks.append(header + "\n" + rows.joined(separator: "\n"))
            }
        }

        return blocks.joined(separator: "\n")
    }
}
