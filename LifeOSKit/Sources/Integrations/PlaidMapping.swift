import Foundation
import Persistence

public enum PlaidMappingError: Error, Equatable {
    /// Plaid sent a date this app cannot read. Loud on purpose: see below.
    case unreadableDate(String)
}

/// Turns Plaid's vocabulary into this app's.
///
/// The single most important line here is the negation. Plaid's `amount` is
/// positive when money leaves the account; `MoneyEntry`'s convention is that
/// positive is money in. Get this backwards and salary becomes the month's
/// largest expense, the savings rate inverts, and nothing crashes.
public enum PlaidMapping {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed format needs a fixed locale, or a device set to a non-Gregorian
        // calendar parses this differently.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Throws rather than skipping a row it cannot read. A silently dropped
    /// transaction is a wrong total with no error anywhere in the app; a thrown
    /// error fails the sync and leaves the last known-good snapshot on screen.
    public static func ingestRows(
        from transactions: [PlaidTransaction],
        accounts: [PlaidAccount] = []
    ) throws -> [MoneyIngestRow] {
        let namesByID = Dictionary(
            accounts.map { ($0.account_id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        return try transactions.map { transaction in
            guard let date = dateFormatter.date(from: transaction.date) else {
                throw PlaidMappingError.unreadableDate(transaction.date)
            }
            return MoneyIngestRow(
                externalID: transaction.transaction_id,
                date: date,
                amount: -transaction.amount,
                merchant: transaction.merchant_name ?? transaction.name,
                category: PlaidCategory.display(primary: transaction.personal_finance_category?.primary),
                categoryCode: transaction.personal_finance_category?.detailed,
                pending: transaction.pending,
                accountID: transaction.account_id,
                accountName: namesByID[transaction.account_id],
                currencyCode: transaction.iso_currency_code ?? "USD"
            )
        }
    }

    public static func accountRows(from accounts: [PlaidAccount]) -> [MoneyAccountRow] {
        accounts.map { account in
            MoneyAccountRow(
                externalID: account.account_id,
                name: account.name,
                type: account.type,
                // A null balance means Plaid could not read it this time. Zero is
                // the honest placeholder; the next sync corrects it.
                currentBalance: account.balances.current ?? 0,
                currencyCode: account.balances.iso_currency_code ?? "USD"
            )
        }
    }
}
