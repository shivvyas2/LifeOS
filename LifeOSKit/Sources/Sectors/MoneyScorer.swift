import Foundation
import Persistence

/// Money, from this month's transactions.
///
/// **Sign convention, inherited from `MoneyEntry`: positive is money in,
/// negative is money out.** A flip here turns every good month into a bad one,
/// which is why the split is done once, at the top, and named.
public struct MoneyScorer: SectorScorer {
    public let sector = LifeSector.money

    private let amounts: [Double]
    private let previousAmounts: [Double]

    public init(amounts: [Double], previousAmounts: [Double]) {
        self.amounts = amounts
        self.previousAmounts = previousAmounts
    }

    public func evidence() -> Evidence {
        guard !amounts.isEmpty else { return Evidence() }

        let earned = amounts.filter { $0 > 0 }.reduce(0, +)
        let spent = -amounts.filter { $0 < 0 }.reduce(0, +)

        var rows = [
            EvidenceRow(label: "earned", value: Self.money(earned), normalised: 0, weight: 0),
            EvidenceRow(label: "spent", value: Self.money(spent), normalised: 0, weight: 0),
        ]

        // A month that earned nothing cannot have a saving rate. It scores
        // poorly rather than perfectly, and says why.
        let savingRate = earned > 0 ? (earned - spent) / earned : 0
        rows.append(EvidenceRow(
            label: "kept of what came in",
            value: earned > 0 ? "\(Int((savingRate * 100).rounded()))%" : "no income",
            normalised: savingRate / 0.5,  // Relies on EvidenceRow clamping above 1.0
            weight: 3
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

        return Evidence(rows)
    }

    private static func money(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
