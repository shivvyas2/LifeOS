import Testing
import Foundation
import Persistence
@testable import Sectors

@Suite struct BudgetPeriodTests {
    private let eatingOut = BudgetBucket(
        name: "Eating out", monthlyLimit: 300,
        claimed: ["FOOD_AND_DRINK_RESTAURANTS", "FOOD_AND_DRINK_FAST_FOOD"]
    )

    /// A refund arrives positive in a spend category. It must reduce that
    /// bucket's spent figure, never inflate income or unclaimed spend.
    @Test func aRefundNetsWithinItsBucket() {
        let report = BudgetPeriod.assess(buckets: [eatingOut], lines: [
            SpendLine(key: "FOOD_AND_DRINK_RESTAURANTS", label: "Food & drink", amount: -120),
            SpendLine(key: "FOOD_AND_DRINK_RESTAURANTS", label: "Food & drink", amount: 40),
        ])
        #expect(report.rows.first?.spent == 80)
        #expect(report.unclaimed.isEmpty)
    }

    @Test func aClaimedKeyCountsInItsBucketAndNowhereElse() {
        let report = BudgetPeriod.assess(buckets: [eatingOut], lines: [
            SpendLine(key: "FOOD_AND_DRINK_FAST_FOOD", label: "Food & drink", amount: -55),
        ])
        #expect(report.rows == [BudgetReport.Row(
            id: eatingOut.id, name: "Eating out", limit: 300, spent: 55,
            adherence: 1
        )])
        #expect(report.unclaimed.isEmpty)
    }

    /// Income nets positive under its key, so it never shows as unclaimed
    /// spend; only net outflows do.
    @Test func incomeNeverAppearsAsUnclaimedSpend() {
        let report = BudgetPeriod.assess(buckets: [eatingOut], lines: [
            SpendLine(key: "INCOME_WAGES", label: "Income", amount: 5_200),
            SpendLine(key: "ENTERTAINMENT_MUSIC", label: "Entertainment", amount: -30),
        ])
        #expect(report.unclaimed == [BudgetReport.Unclaimed(
            key: "ENTERTAINMENT_MUSIC", label: "Entertainment", amount: 30, count: 1
        )])
    }

    @Test func uncategorisedSpendGroupsUnderTheNilKey() {
        let report = BudgetPeriod.assess(buckets: [], lines: [
            SpendLine(key: nil, label: nil, amount: -25),
            SpendLine(key: nil, label: nil, amount: -15),
        ])
        #expect(report.unclaimed == [BudgetReport.Unclaimed(
            key: nil, label: nil, amount: 40, count: 2
        )])
    }

    @Test func unclaimedComesBackLargestFirst() {
        let report = BudgetPeriod.assess(buckets: [], lines: [
            SpendLine(key: "MEDICAL_DENTAL", label: "Medical", amount: -60),
            SpendLine(key: "TRAVEL_FLIGHTS", label: "Travel", amount: -400),
        ])
        #expect(report.unclaimed.map(\.key) == ["TRAVEL_FLIGHTS", "MEDICAL_DENTAL"])
    }

    @Test func adherenceIsPerfectAtOrUnderTheLimit() {
        #expect(BudgetPeriod.adherence(spent: 0, limit: 300) == 1)
        #expect(BudgetPeriod.adherence(spent: 300, limit: 300) == 1)
    }

    /// A bucket 1% over must not read the same as one at triple its limit:
    /// linear decay, hitting zero when the overspend equals the limit again.
    @Test func adherenceDegradesLinearlyToZeroAtDoubleTheLimit() {
        #expect(BudgetPeriod.adherence(spent: 450, limit: 300) == 0.5)
        #expect(BudgetPeriod.adherence(spent: 600, limit: 300) == 0)
        #expect(BudgetPeriod.adherence(spent: 900, limit: 300) == 0)
    }

    @Test func keptCountAndMeanAdherenceSummarise() {
        let over = BudgetBucket(name: "Over", monthlyLimit: 100, claimed: ["A"])
        let under = BudgetBucket(name: "Under", monthlyLimit: 100, claimed: ["B"])
        let report = BudgetPeriod.assess(buckets: [over, under], lines: [
            SpendLine(key: "A", label: nil, amount: -200),
            SpendLine(key: "B", label: nil, amount: -50),
        ])
        #expect(report.keptCount == 1)
        #expect(report.meanAdherence == 0.5)
    }

    @Test func noBucketsMeansNoMeanAdherence() {
        #expect(BudgetPeriod.assess(buckets: [], lines: []).meanAdherence == nil)
    }

    /// The one entry filter, shared by the screen and the close: pending and
    /// transfer-like entries drop, and the raw code beats the display label.
    @Test @MainActor func linesDropPendingAndTransfersAndPreferTheCode() {
        let entries = [
            MoneyEntry(date: .now, amount: -50, merchant: "Shop",
                       category: "Shopping", categoryCode: "GENERAL_MERCHANDISE_SUPERSTORES"),
            MoneyEntry(date: .now, amount: -999, merchant: "Hold", pending: true),
            MoneyEntry(date: .now, amount: -400, merchant: "Card payment",
                       categoryCode: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"),
            MoneyEntry(date: .now, amount: -12, merchant: "Cafe", category: "Coffee"),
        ]
        let lines = BudgetPeriod.lines(from: entries)
        #expect(lines.map(\.key) == ["GENERAL_MERCHANDISE_SUPERSTORES", "Coffee"])
        #expect(lines.first?.label == "Shopping")
    }
}
