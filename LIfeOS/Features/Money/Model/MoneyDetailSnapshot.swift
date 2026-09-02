import Foundation

/// One category or one merchant, on a page of its own.
struct MoneyDetailSnapshot: Equatable {
    var filter: MoneyDetailFilter?
    var logoURL: URL?
    var category: String?
    var monthTotal: Double = 0
    var monthCount: Int = 0
    /// Six months, oldest first, the last one current.
    var months: [MonthSpend] = []
    /// Mean of the completed months that had anything. Nil until one has.
    var average: Double?
    /// This month's matching rows, most recent first.
    var transactions: [MoneyRow] = []
    var monthLabel: String = ""
}
