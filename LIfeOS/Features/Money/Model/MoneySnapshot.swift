import Foundation

struct MoneySnapshot: Equatable {
    var income: Double = 0
    var expenses: Double = 0
    var net: Double = 0
    /// Nil when there is no income: undefined, not zero.
    var savingsRate: Double?
    var netWorth: Double?
    var recent: [MoneyRow] = []
    var budgets: [BudgetBandRow] = []
    var unclaimed: [UnclaimedBandRow] = []
    var monthLabel: String = ""
    /// These figures are invented, not this person's money. Carried on the
    /// snapshot rather than read from defaults at the point of display, so
    /// every screen rendering a sample month is holding the fact that says so.
    var isSample = false
    var isConnected = false
    /// A bank is linked, whether or not any transaction has arrived yet.
    var hasConnectedBank = false
    /// Linked, but Plaid is still assembling the history. Distinct from an
    /// empty month, and the screen must not present it as one.
    var isFetchingHistory = false
    /// Set when a bank has invalidated its stored login.
    var reconnectPrompt: String?
    var lastSyncedAt: Date?

    var verdict: String {
        guard let savingsRate else { return "No income logged" }
        return savingsRate >= 0.2 ? "On track" : (savingsRate >= 0 ? "Tight" : "Overspending")
    }
}

struct MoneyRow: Equatable, Identifiable {
    let id: UUID
    let merchant: String
    let category: String?
    let amount: Double
    let date: Date
    let pending: Bool
}

struct BudgetBandRow: Equatable, Identifiable {
    let id: UUID
    let name: String
    let limit: Double
    let spent: Double

    var isOver: Bool { spent > limit }
    var progress: Double { limit > 0 ? min(spent / limit, 1) : 0 }
}

struct UnclaimedBandRow: Equatable, Identifiable {
    /// The claim key, or "uncategorised" for the nil key.
    let id: String
    let label: String
    let amount: Double
    let count: Int
}
