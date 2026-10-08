import Foundation
import SwiftData

/// "Always use this card for this merchant."
///
/// Resolved when rows are read, not written onto them, so a rule made today
/// relabels last month's charges too, and deleting it puts them back. Writing
/// it onto rows would also have to happen inside `ingest`, on every resend.
@Model
public final class MerchantCardRule {
    public var id: UUID
    /// `CardResolver.merchantKey` of the merchant name.
    public var merchantKey: String
    /// A `MoneyAccount.cardKey`.
    public var cardKey: String
    public var createdAt: Date

    public init(merchantKey: String, cardKey: String) {
        self.id = UUID()
        self.merchantKey = merchantKey
        self.cardKey = cardKey
        self.createdAt = .now
    }
}

/// Which card paid for a transaction.
///
/// Most specific statement wins: a card picked on that one row, then a rule
/// for its merchant, then the account Plaid reported. Pure, so the precedence
/// is tested without a store.
public struct CardResolver: Sendable {
    private let rules: [String: String]

    public init(rules: [String: String] = [:]) {
        self.rules = rules
    }

    public init(rules: [MerchantCardRule]) {
        self.rules = rules.reduce(into: [:]) { $0[$1.merchantKey] = $1.cardKey }
    }

    public func cardKey(for entry: MoneyEntry) -> String? {
        cardKey(override: entry.cardOverrideKey, merchant: entry.merchant, accountID: entry.accountID)
    }

    public func cardKey(override: String?, merchant: String, accountID: String?) -> String? {
        if let override { return override }
        if let ruled = rules[Self.merchantKey(merchant)] { return ruled }
        return accountID
    }

    /// One key per merchant however the name is cased or padded, so "Amazon"
    /// and "AMAZON " share a rule.
    public static func merchantKey(_ merchant: String) -> String {
        merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
