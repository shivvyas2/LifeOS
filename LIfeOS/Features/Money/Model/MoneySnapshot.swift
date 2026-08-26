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
    /// Where the money actually went, largest first. Derived from `recent`
    /// rather than stored, because a category total that disagreed with the
    /// transactions under it would be the screen contradicting itself.
    var categories: [CategoryRow] = []
    /// Merchants that bill every month. Detected from history, not declared:
    /// nothing in the data says "subscription".
    var recurring: [RecurringRow] = []
    /// What the month is saving towards, when a target has been set.
    var goal: SavingsGoal?
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

/// One spending category with its share of the month.
struct CategoryRow: Equatable, Identifiable {
    let id: String
    let name: String
    let amount: Double
    /// Share of total spend, 0...1. Precomputed so the view never divides by a
    /// total it would have to be handed separately and could get wrong.
    let share: Double
}

/// A merchant that bills every month.
struct RecurringRow: Equatable, Identifiable {
    let id: String
    let merchant: String
    let category: String?
    let amount: Double
    /// How many distinct months this merchant has charged in.
    let months: Int
}

/// A savings target and how far along it is.
struct SavingsGoal: Equatable {
    let name: String
    let target: Double
    let saved: Double

    /// 0...1, clamped: a goal passed is full, never more than full, because a
    /// bar drawn past its own end reads as a rendering bug.
    var progress: Double { target > 0 ? min(saved / target, 1) : 0 }
    var remaining: Double { max(target - saved, 0) }
    var isMet: Bool { saved >= target && target > 0 }
}

/// Something costing more than it should this month.
///
/// Assembled by the view model from budgets and recurring spend, so the screen
/// has one list to render rather than three rules to apply.
struct PressurePoint: Equatable, Identifiable {
    let id: String
    let title: String
    /// A plain sentence saying what is wrong, in the app's voice.
    let detail: String
    let amount: Double
}
