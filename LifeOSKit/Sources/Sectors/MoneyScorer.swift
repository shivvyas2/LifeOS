import Foundation
import Persistence

/// Money, from this month's transactions.
///
/// **Sign convention, inherited from `MoneyEntry`: positive is money in,
/// negative is money out.** A flip here turns every good month into a bad one,
/// which is why the split is done once, at the top, and named.
///
/// With buckets, adherence takes the top weight and the saving rate steps
/// down: a budget is a plan you set, and beating it measures what you decided
/// mattered, where a saving rate measures what happened to be left over. With
/// no buckets the evidence is exactly what it was before budgets existed.
public struct MoneyScorer: SectorScorer {
    public let sector = LifeSector.money

    private let amounts: [Double]
    private let previousAmounts: [Double]
    private let budget: BudgetReport?

    public init(amounts: [Double], previousAmounts: [Double], budget: BudgetReport? = nil) {
        self.amounts = amounts
        self.previousAmounts = previousAmounts
        self.budget = budget
    }

    public func evidence() -> Evidence {
        guard !amounts.isEmpty else { return Evidence() }

        let earned = amounts.filter { $0 > 0 }.reduce(0, +)
        let spent = -amounts.filter { $0 < 0 }.reduce(0, +)
        let adherence = budget?.meanAdherence

        var rows = [
            EvidenceRow(label: "earned", value: Self.money(earned), normalised: 0, weight: 0),
            EvidenceRow(label: "spent", value: Self.money(spent), normalised: 0, weight: 0),
        ]

        if let budget, let adherence {
            rows.append(EvidenceRow(
                label: "budgets kept",
                value: "\(budget.keptCount)/\(budget.rows.count)",
                normalised: adherence,
                weight: 3
            ))
        }

        // A month that earned nothing cannot have a saving rate. It scores
        // poorly rather than perfectly, and says why.
        let savingRate = earned > 0 ? (earned - spent) / earned : 0
        rows.append(EvidenceRow(
            label: "kept of what came in",
            value: earned > 0 ? "\(Int((savingRate * 100).rounded()))%" : "no income",
            normalised: savingRate / 0.5,  // Relies on EvidenceRow clamping above 1.0 (high savings) and below 0.0 (spending more than earning)
            weight: adherence == nil ? 3 : 2
        ))

        let previousSpend = -previousAmounts.filter { $0 < 0 }.reduce(0, +)
        if previousSpend > 0 {
            let change = (previousSpend - spent) / previousSpend
            rows.append(EvidenceRow(
                label: "spend vs last month",
                value: "\(change >= 0 ? "-" : "+")\(Int((abs(change) * 100).rounded()))%",
                normalised: 0.5 + change,  // Relies on EvidenceRow clamping above 1.0 and below 0.0
                weight: 1
            ))
        }

        // A gap in the category mapping, not a judgement on the person:
        // shown so it can be fixed, kept out of the arithmetic.
        if let budget, budget.unclaimedTotal > 0 {
            rows.append(EvidenceRow(
                label: "unclaimed", value: Self.money(budget.unclaimedTotal),
                normalised: 0, weight: 0
            ))
        }

        return Evidence(rows)
    }

    private static func money(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
