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

    /// Renders the bundle for one audience within a character budget.
    ///
    /// `.onDevice` keeps the render to the digest plus one sector line: the
    /// local window is small and a transaction list would push the health
    /// data out of it. `.offDevice` carries everything, and trims the
    /// cheapest-to-lose detail first: transactions, oldest last.
    public func promptLines(for audience: MetricsDigest.Audience, budget: Int = 8_000) -> String {
        var blocks: [String] = []
        if let firstName { blocks.append("User: \(firstName)") }
        blocks.append(digest.promptLines(for: audience))

        if !sectors.isEmpty {
            let scores = sectors.map { sector in
                guard let score = sector.score else { return "\(sector.name) unscored" }
                let delta = sector.delta.map { $0 >= 0 ? " (+\($0))" : " (\($0))" } ?? ""
                return "\(sector.name) \(score)\(delta)"
            }
            blocks.append("Life sectors: " + scores.joined(separator: ", "))
        }

        if let money {
            var line = "Money this month: income \(Int(money.income)), expenses \(Int(money.expenses))"
            if let rate = money.savingsRate { line += ", saved \(Int(rate * 100))%" }
            if let netWorth = money.netWorth { line += ", net worth \(Int(netWorth))" }
            blocks.append(line)

            // Raw transaction rows are the cheapest, least dense line in the
            // bundle, so they are the only thing trimmed for budget. Everything
            // above this point renders unconditionally.
            if audience == .offDevice {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                var rows: [String] = []
                var spent = blocks.joined(separator: "\n").count
                for transaction in money.recent {
                    let row = "\(formatter.string(from: transaction.date)) \(transaction.merchant)"
                        + (transaction.category.map { " (\($0))" } ?? "")
                        + " \(String(format: "%.2f", transaction.amount))"
                    guard spent + row.count + 1 <= budget else { break }
                    rows.append(row)
                    spent += row.count + 1
                }
                if !rows.isEmpty {
                    blocks.append("Recent transactions:\n" + rows.joined(separator: "\n"))
                }
            }
        }

        return blocks.joined(separator: "\n")
    }
}
