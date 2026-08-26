import Foundation

/// Plaid's `personal_finance_category.primary`, turned into something a person
/// would read.
///
/// A fixed table rather than a general un-shout of the raw string: Plaid's
/// codes are a closed vocabulary Plaid controls, and a generic transform gives
/// "General merchandise" and "Food and drink" without the ampersand this app
/// uses. An unrecognised code returns nil, so a category Plaid adds next year
/// shows as uncategorised instead of shouting from the transaction list.
public enum PlaidCategory {
    private static let labels: [String: String] = [
        "INCOME": "Income",
        "TRANSFER_IN": "Transfer in",
        "TRANSFER_OUT": "Transfer out",
        "LOAN_PAYMENTS": "Loan payments",
        "BANK_FEES": "Bank fees",
        "ENTERTAINMENT": "Entertainment",
        "FOOD_AND_DRINK": "Food & drink",
        "GENERAL_MERCHANDISE": "Shopping",
        "HOME_IMPROVEMENT": "Home",
        "MEDICAL": "Medical",
        "PERSONAL_CARE": "Personal care",
        "GENERAL_SERVICES": "Services",
        "GOVERNMENT_AND_NON_PROFIT": "Government & giving",
        "TRANSPORTATION": "Transport",
        "TRAVEL": "Travel",
        "RENT_AND_UTILITIES": "Rent & utilities",
    ]

    public static func display(primary: String?) -> String? {
        guard let primary else { return nil }
        return labels[primary]
    }
}
