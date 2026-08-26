import Foundation
import Persistence

/// One countable transaction, reduced to what budgeting needs. `label` is the
/// display string the transaction list already shows, carried for the
/// unclaimed view; it never keys arithmetic.
public struct SpendLine: Sendable, Equatable {
    public let key: String?
    public let label: String?
    public let amount: Double

    public init(key: String?, label: String?, amount: Double) {
        self.key = key
        self.label = label
        self.amount = amount
    }
}

/// A bucket as a plain value, so `assess` stays pure and its tests need no
/// container.
public struct BudgetBucket: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let monthlyLimit: Double
    public let claimed: Set<String>
    public let sortOrder: Int

    public init(id: UUID = UUID(), name: String, monthlyLimit: Double,
                claimed: Set<String>, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.monthlyLimit = monthlyLimit
        self.claimed = claimed
        self.sortOrder = sortOrder
    }

    @MainActor
    public init(_ model: SpendBucket) {
        self.init(id: model.id, name: model.name, monthlyLimit: model.monthlyLimit,
                  claimed: Set(model.claimedRaw), sortOrder: model.sortOrder)
    }
}

/// One month's budgets, measured.
public struct BudgetReport: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let id: UUID
        public let name: String
        public let limit: Double
        public let spent: Double
        /// 1.0 at or under the limit, degrading linearly to 0 when the
        /// overspend reaches the limit again.
        public let adherence: Double

        public var isKept: Bool { spent <= limit }

        public init(id: UUID, name: String, limit: Double, spent: Double, adherence: Double) {
            self.id = id
            self.name = name
            self.limit = limit
            self.spent = spent
            self.adherence = adherence
        }
    }

    /// Net outflow no bucket claims. First-class, never silently dropped:
    /// the whole point of buckets over raw strings was that nothing stops
    /// counting quietly.
    public struct Unclaimed: Sendable, Equatable {
        public let key: String?
        public let label: String?
        public let amount: Double
        public let count: Int

        public init(key: String?, label: String?, amount: Double, count: Int) {
            self.key = key
            self.label = label
            self.amount = amount
            self.count = count
        }
    }

    public let rows: [Row]
    public let unclaimed: [Unclaimed]

    public init(rows: [Row], unclaimed: [Unclaimed]) {
        self.rows = rows
        self.unclaimed = unclaimed
    }

    public var keptCount: Int { rows.filter(\.isKept).count }

    /// Nil with no buckets: no evidence, no number, never a zero.
    public var meanAdherence: Double? {
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + $1.adherence } / Double(rows.count)
    }

    public var unclaimedTotal: Double { unclaimed.reduce(0) { $0 + $1.amount } }
}

public enum BudgetPeriod {
    /// The one place the entry filter lives. Both call sites, the Money
    /// screen and the monthly close, come through here, so the two cannot
    /// drift: pending entries drop, transfer-like codes drop (a card payment
    /// must not surface as unclaimed spend), and the claim key prefers the
    /// raw code over the display label.
    @MainActor
    public static func lines(from entries: [MoneyEntry]) -> [SpendLine] {
        entries
            .filter { !$0.pending && !MoneyCategoryRule.isTransferLike($0.categoryCode) }
            .map { SpendLine(key: $0.claimKey, label: $0.category, amount: $0.amount) }
    }

    public static func assess(buckets: [BudgetBucket], lines: [SpendLine]) -> BudgetReport {
        var netByKey: [String?: Double] = [:]
        var countByKey: [String?: Int] = [:]
        var labelByKey: [String?: String] = [:]
        for line in lines {
            netByKey[line.key, default: 0] += line.amount
            countByKey[line.key, default: 0] += 1
            if let label = line.label { labelByKey[line.key] = label }
        }

        let rows = buckets
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map { bucket in
                // Netting across the bucket's keys is what makes a refund
                // reduce spend instead of inflating income.
                let net = bucket.claimed.reduce(0) { $0 + (netByKey[$1] ?? 0) }
                let spent = max(0, -net)
                return BudgetReport.Row(
                    id: bucket.id, name: bucket.name, limit: bucket.monthlyLimit,
                    spent: spent, adherence: adherence(spent: spent, limit: bucket.monthlyLimit)
                )
            }

        let claimedKeys = Set(buckets.flatMap(\.claimed))
        let unclaimed = netByKey
            .filter { key, net in
                net < 0 && !(key.map(claimedKeys.contains) ?? false)
            }
            .map { key, net in
                BudgetReport.Unclaimed(
                    key: key, label: labelByKey[key],
                    amount: -net, count: countByKey[key] ?? 0
                )
            }
            .sorted { $0.amount > $1.amount }

        return BudgetReport(rows: rows, unclaimed: unclaimed)
    }

    /// At or under the limit is 1.0; over, linear decay reaching 0 when the
    /// overspend equals the limit again.
    static func adherence(spent: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        guard spent > limit else { return 1 }
        return max(0, 1 - (spent - limit) / limit)
    }
}
