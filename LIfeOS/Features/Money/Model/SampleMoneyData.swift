import Foundation

/// A month of invented finances, so the Money screen can be looked at before
/// Plaid is wired and there is any real data to look at.
///
/// This deliberately ships in release builds, because bank connection is
/// broken and TestFlight testers otherwise see an empty screen and can judge
/// nothing. That removes the `#if DEBUG` that used to be the whole safety
/// story, so the labelling replaces it: `isSample` travels with the snapshot
/// and the Money screen states on the screen itself that the figures are
/// invented. Numbers a viewer could mistake for their own money must never be
/// presented as real, and a toggle buried in Settings is not something a
/// tester who opens the app tomorrow will remember flipping.
///
/// When Plaid works, delete this file, the toggle, and the badge together.
///
/// The numbers are deliberately unremarkable — a salary, a rent payment, a
/// grocery run — because the point is to see how the layout handles a normal
/// month, not to admire a interesting one.
extension MoneySnapshot {
    static var sample: MoneySnapshot {
        let income = 6_200.0
        let expenses = 4_431.58
        let net = income - expenses

        return MoneySnapshot(
            income: income,
            expenses: expenses,
            net: net,
            savingsRate: net / income,
            netWorth: 48_260.14,
            recent: sampleRows,
            budgets: sampleBudgets,
            unclaimed: sampleUnclaimed,
            monthLabel: Date.now.formatted(.dateTime.month(.wide).year()),
            isSample: true,
            isConnected: true
        )
    }

    /// One bucket comfortably inside its limit, one just under, and one over.
    /// A sample where every bucket is healthy would never show the band's
    /// over-budget treatment, which is the state most worth looking at.
    private static var sampleBudgets: [BudgetBandRow] {
        [
            BudgetBandRow(id: UUID(), name: "Groceries", limit: 600, spent: 412.87),
            BudgetBandRow(id: UUID(), name: "Eating out", limit: 250, spent: 238.40),
            BudgetBandRow(id: UUID(), name: "Transport", limit: 120, spent: 163.15),
        ]
    }

    /// Spend no bucket claims. Present deliberately: the band exists to prove
    /// nothing stops being counted quietly, and a sample with nothing unclaimed
    /// would hide the one row that makes that point.
    private static var sampleUnclaimed: [UnclaimedBandRow] {
        [
            UnclaimedBandRow(id: "subscriptions", label: "Subscriptions", amount: -47.97, count: 3),
            UnclaimedBandRow(id: "uncategorised", label: "Uncategorised", amount: -88.20, count: 2),
        ]
    }

    /// Dated backwards from today rather than pinned to fixed dates, so the rows
    /// stay plausibly recent however long this sits here before Plaid arrives.
    private static var sampleRows: [MoneyRow] {
        let day = 86_400.0
        let entries: [(String, String?, Double, Double, Bool)] = [
            ("Whole Foods",        "Groceries",      -134.22, 0,  true),
            ("Acme Corp",          "Salary",         6_200.00, 1, false),
            ("Riverside Lofts",    "Rent",          -2_150.00, 2, false),
            ("Con Edison",         "Utilities",       -118.40, 3, false),
            ("Uber",               "Transport",        -27.85, 4, false),
            ("Blue Bottle Coffee", "Dining",           -18.50, 5, false),
            ("Spotify",            "Subscriptions",    -11.99, 6, false),
            ("Trader Joe's",       "Groceries",        -86.31, 8, false),
        ]

        return entries.map { merchant, category, amount, daysAgo, pending in
            MoneyRow(
                id: UUID(),
                merchant: merchant,
                category: category,
                amount: amount,
                date: Date.now.addingTimeInterval(-daysAgo * day),
                pending: pending
            )
        }
    }
}
