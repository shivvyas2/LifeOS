import Foundation

struct MoneySnapshot: Equatable {
    var income: Double = 0
    var expenses: Double = 0
    var net: Double = 0
    /// Nil when there is no income — undefined, not zero.
    var savingsRate: Double?
    var netWorth: Double?
    var recent: [MoneyRow] = []
    var monthLabel: String = ""
    var isConnected = false

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
