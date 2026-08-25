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
}
