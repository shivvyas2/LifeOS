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
    /// Plaid sends a bare calendar date, "2026-08-24", with no time in it.
    ///
    /// It must be parsed in the same calendar `MoneyStore` normalizes with,
    /// because the store applies `startOfDay` on the way in. Pinning this to UTC
    /// while the store uses `Calendar.current` puts them a day apart for every
    /// device west of Greenwich: a transaction Plaid dates the 1st is stored as
    /// the 31st in New York, which moves it into the previous month's income and
    /// expense totals.
    private static func parse(_ text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        // Fixed format needs a fixed locale, or a device set to a non-Gregorian
        // calendar parses this differently.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// Throws rather than skipping a row it cannot read. A silently dropped
    /// transaction is a wrong total with no error anywhere in the app; a thrown
    /// error fails the sync and leaves the last known-good snapshot on screen.
    public static func ingestRows(
        from transactions: [PlaidTransaction],
        accounts: [PlaidAccount] = [],
        calendar: Calendar = .current
    ) throws -> [MoneyIngestRow] {
        let namesByID = Dictionary(
            accounts.map { ($0.account_id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        return try transactions.map { transaction in
            guard let date = parse(transaction.date, calendar: calendar) else {
                throw PlaidMappingError.unreadableDate(transaction.date)
            }
            return MoneyIngestRow(
                externalID: transaction.transaction_id,
                date: date,
                amount: -transaction.amount,
                merchant: transaction.merchant_name ?? transaction.name,
                category: PlaidCategory.display(primary: transaction.personal_finance_category?.primary),
                categoryCode: transaction.personal_finance_category?.detailed,
                merchantID: transaction.merchant_entity_id,
                logoURL: transaction.logo_url,
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
                subtype: account.subtype,
                mask: account.mask,
                // A null balance means Plaid could not read it this time. Zero is
                // the honest placeholder; the next sync corrects it.
                currentBalance: account.balances.current ?? 0,
                // Deliberately NOT given the same fallback. A zero balance is a
                // wrong number that the next sync fixes; a zero limit is a wrong
                // number that renders as 100% utilised and looks like a fact.
                availableBalance: account.balances.available,
                creditLimit: account.balances.limit,
                currencyCode: account.balances.iso_currency_code ?? "USD"
            )
        }
    }
}
