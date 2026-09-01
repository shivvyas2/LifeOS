import Foundation

/// What `plaid-sync` returns: one delta per connected Item.
///
/// The function syncs every Item the user has in one call, because the device
/// does not otherwise know what is connected. Everything inside an item delta
/// except `institution_name` is Plaid's own JSON, passed through untouched.
public struct PlaidSyncResponse: Decodable, Sendable {
    public let items: [PlaidItemDelta]
}

public struct PlaidItemDelta: Decodable, Sendable {
    public let item_id: String
    public let institution_name: String
    public let added: [PlaidTransaction]
    public let modified: [PlaidTransaction]
    public let removed: [PlaidRemoved]
    public let accounts: [PlaidAccount]
    public let next_cursor: String?
    public let has_more: Bool
    /// Set when this one Item failed while others succeeded, so one expired
    /// bank login does not fail the whole sync.
    public let error: String?
    /// Set when the balance fetch failed even though the transaction sync
    /// above succeeded. `/transactions/sync` serves cached data and can
    /// succeed with an expired bank login; `/accounts/balance/get` does a live
    /// fetch and is the call that actually throws `ITEM_LOGIN_REQUIRED`. That
    /// is what raises the reconnect banner, not `error`.
    public let balance_error: String?
}

public struct PlaidTransaction: Decodable, Sendable {
    public let transaction_id: String
    public let account_id: String
    /// **Positive is money leaving the account.** The opposite of this app's
    /// convention. `PlaidMapping` negates.
    public let amount: Double
    public let iso_currency_code: String?
    /// ISO 8601 calendar date, "2026-08-24".
    public let date: String
    /// The raw bank descriptor.
    public let name: String
    /// Plaid's cleaned-up merchant, when it has one.
    public let merchant_name: String?
    /// Plaid's stable identifier for the merchant behind this descriptor.
    ///
    /// Nil when Plaid could not resolve one, which is common enough that no
    /// caller may assume presence. It is the right grouping key for recurring
    /// detection because it survives a descriptor changing spelling, which a
    /// merchant name does not: `NETFLIX.COM` and `Netflix` are one entity here
    /// and two strings anywhere else.
    public let merchant_entity_id: String?
    public let pending: Bool
    public let personal_finance_category: PlaidPFC?

    public init(transaction_id: String, account_id: String, amount: Double,
                iso_currency_code: String?, date: String, name: String,
                merchant_name: String?, merchant_entity_id: String? = nil,
                pending: Bool,
                personal_finance_category: PlaidPFC?) {
        self.transaction_id = transaction_id
        self.account_id = account_id
        self.amount = amount
        self.iso_currency_code = iso_currency_code
        self.date = date
        self.name = name
        self.merchant_name = merchant_name
        self.merchant_entity_id = merchant_entity_id
        self.pending = pending
        self.personal_finance_category = personal_finance_category
    }
}

public struct PlaidPFC: Decodable, Sendable {
    public let primary: String
    public let detailed: String
}

public struct PlaidRemoved: Decodable, Sendable {
    public let transaction_id: String
}

public struct PlaidAccount: Decodable, Sendable {
    public let account_id: String
    public let name: String
    /// depository, credit, investment or loan.
    public let type: String
    /// The last two to four characters of the account number. What tells two
    /// cards apart on screen.
    public let mask: String?
    /// Plaid's fine classification: checking, savings, credit card, mortgage.
    ///
    /// Kept alongside `type` rather than replacing it. `type` answers "is this
    /// money owed", which is what net worth needs; `subtype` answers "is this a
    /// credit card", which is what utilisation needs, and a mortgage is a loan
    /// with a balance and no meaningful utilisation.
    public let subtype: String?
    public let balances: PlaidBalances
}

public struct PlaidBalances: Decodable, Sendable {
    public let current: Double?
    /// What can actually be withdrawn, as opposed to what the account holds.
    /// Nil where the institution does not distinguish the two.
    public let available: Double?
    /// The credit limit on a card, or the overdraft limit on a depository
    /// account. Nil at institutions that do not report it, and nil is not zero:
    /// utilisation against a limit of zero is 100% by arithmetic and unknowable
    /// in fact.
    public let limit: Double?
    public let iso_currency_code: String?
}
