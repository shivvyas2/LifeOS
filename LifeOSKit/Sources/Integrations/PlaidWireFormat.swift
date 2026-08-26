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
    /// bank login does not fail the whole sync. `ITEM_LOGIN_REQUIRED` here is
    /// what raises the reconnect banner.
    public let error: String?
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
    public let pending: Bool
    public let personal_finance_category: PlaidPFC?

    public init(transaction_id: String, account_id: String, amount: Double,
                iso_currency_code: String?, date: String, name: String,
                merchant_name: String?, pending: Bool,
                personal_finance_category: PlaidPFC?) {
        self.transaction_id = transaction_id
        self.account_id = account_id
        self.amount = amount
        self.iso_currency_code = iso_currency_code
        self.date = date
        self.name = name
        self.merchant_name = merchant_name
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
    public let balances: PlaidBalances
}

public struct PlaidBalances: Decodable, Sendable {
    public let current: Double?
    public let iso_currency_code: String?
}
