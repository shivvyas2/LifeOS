import Foundation
import SwiftData

public enum MoneySource: String, Codable, Sendable {
    case manual, plaid
}

/// One transaction. Shaped for Plaid ingestion from the start: `externalID`
/// carries `transaction_id` so a re-sync updates rather than duplicates, and
/// `pending` is kept because Plaid re-issues a pending charge with a new id
/// once it settles.
///
/// **Sign convention: positive is money in, negative is money out.**
/// Plaid is the opposite: its `amount` is positive for outflows. The
/// ingestion layer must negate on the way in. This is written down because a
/// silent sign flip turns income into expenses and every rollup lies.
@Model
public final class MoneyEntry {
    public var id: UUID
    /// Plaid `transaction_id`, or nil for a manual entry.
    public var externalID: String?
    public var sourceRaw: String

    /// Always `Calendar.startOfDay` of the transaction date.
    public var date: Date
    /// Positive = income, negative = expense. See the type note.
    public var amount: Double
    public var currencyCode: String

    public var merchant: String
    public var category: String?
    /// Plaid's raw `personal_finance_category.detailed`, or nil for a manual
    /// entry. Kept beside `category` rather than replacing it because
    /// `category` is a display string: keying the rollup rule off display text
    /// would mean renaming a label silently changes the savings rate.
    public var categoryCode: String?
    /// Plaid's `merchant_entity_id`: one stable id for a merchant across every
    /// spelling of its descriptor. Nil for a manual entry, and nil when Plaid
    /// could not resolve one.
    ///
    /// Optional on purpose, and a lightweight SwiftData migration because of
    /// it: rows written before this existed read back nil rather than needing
    /// a migration step.
    public var merchantID: String?
    public var accountID: String?
    public var accountName: String?
    public var pending: Bool

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        date: Date,
        amount: Double,
        merchant: String,
        category: String? = nil,
        categoryCode: String? = nil,
        merchantID: String? = nil,
        currencyCode: String = "USD",
        source: MoneySource = .manual,
        externalID: String? = nil,
        accountID: String? = nil,
        accountName: String? = nil,
        pending: Bool = false
    ) {
        self.id = UUID()
        self.externalID = externalID
        self.sourceRaw = source.rawValue
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.merchant = merchant
        self.category = category
        self.categoryCode = categoryCode
        self.merchantID = merchantID
        self.accountID = accountID
        self.accountName = accountName
        self.pending = pending
        self.createdAt = .now
        self.updatedAt = .now
    }

    public var source: MoneySource {
        get { MoneySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var isIncome: Bool { amount > 0 }
}

/// A funding account and its balance. Net worth is summed from these.
/// Plaid's `/accounts/get` maps onto this directly.
@Model
public final class MoneyAccount {
    public var id: UUID
    /// Plaid `account_id`, or nil for a manually tracked account.
    public var externalID: String?
    public var name: String
    /// Plaid's `type`: depository, credit, investment or loan.
    public var type: String
    public var currentBalance: Double
    public var currencyCode: String
    public var updatedAt: Date

    public init(
        name: String,
        type: String,
        currentBalance: Double,
        currencyCode: String = "USD",
        externalID: String? = nil
    ) {
        self.id = UUID()
        self.externalID = externalID
        self.name = name
        self.type = type
        self.currentBalance = currentBalance
        self.currencyCode = currencyCode
        self.updatedAt = .now
    }

    /// Credit and loan balances are money owed, so they subtract from net worth.
    public var netWorthContribution: Double {
        switch type {
        case "credit", "loan": -abs(currentBalance)
        default: currentBalance
        }
    }
}

/// A month's money position, derived from entries and accounts.
public struct MoneySummary: Sendable, Equatable {
    public var income: Double = 0
    public var expenses: Double = 0
    public var netWorth: Double?

    public init(income: Double = 0, expenses: Double = 0, netWorth: Double? = nil) {
        self.income = income
        self.expenses = expenses
        self.netWorth = netWorth
    }

    public var net: Double { income - expenses }

    /// Share of income kept. Nil when there is no income. A savings rate
    /// against zero income is not 0%, it is undefined, and this app does not
    /// render an invented number.
    public var savingsRate: Double? {
        guard income > 0 else { return nil }
        return (income - expenses) / income
    }
}

/// Which categories are money moving rather than money earned or spent.
///
/// A transfer between your own accounts and a credit card payment both appear
/// as a real debit and a real credit. Counting them leaves `net` correct while
/// overstating income and expenses, and the savings rate is computed from
/// those two, not from net.
public enum MoneyCategoryRule {
    public static func isTransferLike(_ code: String?) -> Bool {
        guard let code else { return false }
        if code == "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT" { return true }
        // Plaid's detailed codes extend the primary with an underscore, e.g.
        // TRANSFER_IN_ACCOUNT_TRANSFER. Match the underscore-delimited prefix
        // rather than listing every detail Plaid may add; without the underscore
        // a code that merely starts with the same letters would be excluded as if
        // it were a transfer.
        return code.hasPrefix("TRANSFER_IN_") || code.hasPrefix("TRANSFER_OUT_")
    }
}

/// Rolls entries into a summary. Pure and testable: no store, no context.
public func summarise(entries: [MoneyEntry], accounts: [MoneyAccount] = []) -> MoneySummary {
    var income = 0.0
    var expenses = 0.0
    for entry in entries where !entry.pending
        && !MoneyCategoryRule.isTransferLike(entry.categoryCode) {
        if entry.amount > 0 { income += entry.amount } else { expenses += -entry.amount }
    }
    return MoneySummary(
        income: income,
        expenses: expenses,
        netWorth: accounts.isEmpty ? nil : accounts.reduce(0) { $0 + $1.netWorthContribution }
    )
}
