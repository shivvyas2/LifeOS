import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct MoneyScorerTests {

    @Test func savingMoreThanHalfOfIncomeScoresWell() {
        let scorer = MoneyScorer(amounts: [5000, -2000], previousAmounts: [])
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! >= 8)
    }

    @Test func spendingMoreThanEarningScoresBadly() {
        let scorer = MoneyScorer(amounts: [3000, -4500], previousAmounts: [])
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! <= 2)
    }

    /// The sign convention is inherited from MoneyEntry and a flip here would
    /// turn every good month into a bad one.
    @Test func positiveIsIncomeAndNegativeIsSpend() {
        let evidence = MoneyScorer(amounts: [4000, -1000], previousAmounts: []).evidence()
        #expect(evidence.rows.first { $0.label == "earned" }?.value == "4000")
        #expect(evidence.rows.first { $0.label == "spent" }?.value == "1000")
    }

    @Test func spendingLessThanLastMonthIsCredited() {
        let scorer = MoneyScorer(amounts: [4000, -1000], previousAmounts: [4000, -2000])
        let row = scorer.evidence().rows.first { $0.label == "spend vs last month" }
        #expect(row != nil)
        #expect(row!.normalised > 0.5)
    }

    @Test func withNoPreviousMonthThereIsNoComparisonRow() {
        let scorer = MoneyScorer(amounts: [4000, -1000], previousAmounts: [])
        #expect(!scorer.evidence().rows.contains { $0.label == "spend vs last month" })
    }

    @Test func aMonthWithNoTransactionsProposesNothing() {
        #expect(MoneyScorer(amounts: [], previousAmounts: []).evidence().proposedScore == nil)
    }

    /// No income and no way to compute a rate must not read as a perfect month.
    @Test func spendWithNoIncomeDoesNotScoreTop() {
        let scorer = MoneyScorer(amounts: [-500], previousAmounts: [])
        let score = scorer.evidence().proposedScore
        #expect(score != nil)
        #expect(score! < 10)
    }

    private func report(spent: Double, limit: Double = 300, unclaimed: Double = 0) -> BudgetReport {
        var lines = [SpendLine(key: "FOOD", label: "Food & drink", amount: -spent)]
        if unclaimed > 0 {
            lines.append(SpendLine(key: "MYSTERY", label: nil, amount: -unclaimed))
        }
        return BudgetPeriod.assess(
            buckets: [BudgetBucket(name: "Eating out", monthlyLimit: limit, claimed: ["FOOD"])],
            lines: lines
        )
    }

    @Test func withBucketsAdherenceLeadsAndTheSavingRateStepsDown() {
        let rows = MoneyScorer(
            amounts: [4_000, -200], previousAmounts: [], budget: report(spent: 200)
        ).evidence().rows

        let adherence = rows.first { $0.label == "budgets kept" }
        #expect(adherence?.value == "1/1")
        #expect(adherence?.weight == 3)
        #expect(adherence?.normalised == 1)
        #expect(rows.first { $0.label == "kept of what came in" }?.weight == 2)
    }

    @Test func aBustedBudgetDragsTheAdherenceRowDown() {
        let rows = MoneyScorer(
            amounts: [4_000, -600], previousAmounts: [], budget: report(spent: 600)
        ).evidence().rows
        let adherence = rows.first { $0.label == "budgets kept" }
        #expect(adherence?.value == "0/1")
        #expect(adherence?.normalised == 0)
    }

    /// No buckets leaves the score exactly as it is today, row for row.
    @Test func withNoBucketsTheEvidenceIsUnchangedFromToday() {
        let evidence = MoneyScorer(amounts: [4_000, -1_000], previousAmounts: []).evidence()
        #expect(!evidence.rows.contains { $0.label == "budgets kept" })
        #expect(!evidence.rows.contains { $0.label == "unclaimed" })
        #expect(evidence.rows.first { $0.label == "kept of what came in" }?.weight == 3)
    }

    /// Unclaimed spend is a gap in the mapping, not a judgement on the
    /// person: shown, never scored.
    @Test func unclaimedSpendIsShownButNeverScored() {
        let rows = MoneyScorer(
            amounts: [4_000, -410], previousAmounts: [],
            budget: report(spent: 200, unclaimed: 210)
        ).evidence().rows
        let row = rows.first { $0.label == "unclaimed" }
        #expect(row?.value == "210")
        #expect(row?.weight == 0)
    }

    @Test func aZeroUnclaimedMonthGetsNoUnclaimedRow() {
        let rows = MoneyScorer(
            amounts: [4_000, -200], previousAmounts: [], budget: report(spent: 200)
        ).evidence().rows
        #expect(!rows.contains { $0.label == "unclaimed" })
    }
}
