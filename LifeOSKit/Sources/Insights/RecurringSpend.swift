import Foundation

/// Finds the payments that come back every month.
///
/// Plaid does not tell us what a subscription is, and the app has no list of
/// them, so the only evidence available is the transaction history itself: a
/// merchant that charges a similar amount at a similar point in consecutive
/// months is a standing cost whether or not anyone called it one. That covers
/// the streaming bills people forget about, which is the whole reason to show
/// this at all.
///
/// Deliberately conservative. A false positive here tells someone they have a
/// subscription they do not have, which is worse than missing one: they go
/// looking for a charge to cancel and find nothing.
public enum RecurringSpend {

    /// One merchant billing on a repeating cycle.
    public struct Charge: Equatable, Sendable, Identifiable {
        public let merchant: String
        public let category: String?
        /// The typical charge, which is the median rather than the mean so one
        /// annual price rise does not drag the figure somewhere that matches
        /// no actual month.
        public let typicalAmount: Double
        /// How many separate months this merchant charged in.
        public let months: Int
        public let lastCharged: Date

        public var id: String { merchant }

        public init(merchant: String, category: String?, typicalAmount: Double,
                    months: Int, lastCharged: Date) {
            self.merchant = merchant
            self.category = category
            self.typicalAmount = typicalAmount
            self.months = months
            self.lastCharged = lastCharged
        }
    }

    /// What a caller has to give us about one charge. Deliberately not the
    /// app's own row type: this module is in the kit and must not know about
    /// the screens that use it.
    public struct Line: Equatable, Sendable {
        public let merchant: String
        public let category: String?
        public let amount: Double
        public let date: Date

        public init(merchant: String, category: String?, amount: Double, date: Date) {
            self.merchant = merchant
            self.category = category
            self.amount = amount
            self.date = date
        }
    }

    /// Merchants charging in at least `minimumMonths` distinct months, at an
    /// amount that stays within `tolerance` of its own median.
    ///
    /// Income is excluded outright. A salary lands every month at a steady
    /// figure and would otherwise be the largest "subscription" on the list.
    public static func charges(
        in lines: [Line],
        minimumMonths: Int = 2,
        tolerance: Double = 0.25,
        calendar: Calendar = .current
    ) -> [Charge] {
        let spend = lines.filter { $0.amount < 0 }
        let byMerchant = Dictionary(grouping: spend) { $0.merchant }

        return byMerchant.compactMap { merchant, charges -> Charge? in
            // Distinct months, not distinct charges: two coffees in one week
            // are not a subscription, and counting rows would call them one.
            let months = Set(charges.map {
                calendar.dateComponents([.year, .month], from: $0.date)
            })
            guard months.count >= minimumMonths else { return nil }

            let amounts = charges.map { abs($0.amount) }.sorted()
            let median = amounts[amounts.count / 2]
            guard median > 0 else { return nil }

            // Every charge has to look like the same bill. A merchant you
            // happen to buy from monthly at wildly different amounts is a
            // habit, not a standing payment, and calling it one would send
            // someone hunting for a subscription to cancel.
            let steady = amounts.allSatisfy { abs($0 - median) / median <= tolerance }
            guard steady else { return nil }

            guard let last = charges.map(\.date).max() else { return nil }
            return Charge(
                merchant: merchant,
                category: charges.first?.category,
                typicalAmount: median,
                months: months.count,
                lastCharged: last
            )
        }
        // Biggest standing cost first: the point of the list is what to cancel.
        .sorted { ($0.typicalAmount, $0.merchant) > ($1.typicalAmount, $1.merchant) }
    }

    /// What these charges cost every month together.
    public static func monthlyTotal(of charges: [Charge]) -> Double {
        charges.reduce(0) { $0 + $1.typicalAmount }
    }
}
