import Foundation
import Testing
@testable import Insights

struct ContextBundleTests {
    private func bundle(transactions: Int = 3) -> ContextBundle {
        let recent = (0..<transactions).map {
            ContextBundle.Money.Transaction(
                merchant: "Merchant \($0)", category: "Food",
                amount: -12.5, date: Date(timeIntervalSince1970: 1_756_000_000)
            )
        }
        return ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(
                income: 8000, expenses: 5000, savingsRate: 0.37,
                netWorth: 25_000, recent: recent
            ),
            sectors: [
                ContextBundle.Sector(name: "Body", score: 7, delta: 1),
                ContextBundle.Sector(name: "Money", score: nil, delta: nil),
            ],
            firstName: "Shiv"
        )
    }

    @Test func theOffDeviceRenderCarriesEverySection() {
        let lines = bundle().promptLines(for: .offDevice)
        #expect(lines.contains("Merchant 0"))
        #expect(lines.contains("Body 7 (+1)"))
        #expect(lines.contains("Money unscored"))
        #expect(lines.contains("Shiv"))
    }

    // The on-device window is small; transactions would drown the digest.
    @Test func theOnDeviceRenderSkipsTransactionDetail() {
        let lines = bundle().promptLines(for: .onDevice)
        #expect(!lines.contains("Merchant 0"))
        #expect(lines.contains("Body 7 (+1)"))
    }

    // Truncation drops transaction detail first; sectors and the money
    // summary survive because they are the cheapest, densest lines.
    @Test func aTightBudgetDropsTransactionsBeforeSummary() {
        let lines = bundle(transactions: 200).promptLines(for: .offDevice, budget: 600)
        #expect(!lines.contains("Merchant 150"))
        #expect(lines.contains("income 8000"))
    }
}
