import Foundation
import Testing
import SwiftData
import Persistence
@testable import Insights

@Suite @MainActor struct ContextBundleTests {
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

    // A fully populated fortnight, the same fixture MetricsDigestTests pins
    // at the digest's own 6000-character default. It renders well under that
    // default, so a bundle that forgot to forward its own tighter budget
    // down to the digest would render every day in full regardless of what
    // budget the bundle itself was asked for.
    private func fortnightDigest() throws -> MetricsDigest {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MetricsStore(context: ModelContext(container))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
        var dates: [Date] = []
        var sleeps: [SleepRecord] = []
        var workouts: [WorkoutRecord] = []

        for offset in 0..<14 {
            let d = day.addingTimeInterval(Double(offset) * 86_400)
            dates.append(d)
            try store.upsert(date: d) {
                $0.whoopRecoveryPct = 51; $0.sleepMinutes = 400; $0.whoopDayStrain = 12.1
                $0.steps = 8_420; $0.exerciseMinutes = 45; $0.hrvMs = 38; $0.restingHR = 61
                $0.spo2Percentage = 95; $0.skinTempCelsius = 33.7; $0.respiratoryRate = 16.1
                $0.whoopSleepPerformancePct = 82; $0.whoopSleepEfficiencyPct = 91
                $0.whoopSleepDebtMinutes = 21
            }
            let night = SleepRecord(externalID: "n\(offset)", start: d, end: d.addingTimeInterval(24_000),
                                    attributedDate: d)
            night.remMinutes = 62; night.swsMinutes = 80; night.lightMinutes = 190
            night.awakeMinutes = 22; night.sleepNeedMinutes = 485
            night.needFromStrainMinutes = 8; night.isNap = false
            sleeps.append(night)

            let w = WorkoutRecord(externalID: "w\(offset)", start: d.addingTimeInterval(3_600),
                                  durationMinutes: 92, activityName: "cycling")
            w.strain = 11.4; w.averageHR = 141
            w.zoneThreeMinutes = 20; w.zoneFourMinutes = 15; w.zoneFiveMinutes = 7
            workouts.append(w)
        }

        return MetricsDigest.from(
            metrics: try store.metrics(from: dates.first!, to: dates.last!),
            sleeps: sleeps, workouts: workouts
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

    // Regression pin: `budget` must reach the digest, not just cap the
    // bundle's own sections. A fortnight of real health data renders well
    // under the digest's own 6000-character default, so a bundle that never
    // forwarded its budget would render every day in full here regardless of
    // how tight a budget it was actually asked for.
    @Test func aNonTrivialDigestStaysWithinTheRequestedBudget() throws {
        let bundle = ContextBundle(digest: try fortnightDigest())
        let lines = bundle.promptLines(for: .offDevice, budget: 800)
        #expect(lines.count <= 800)
    }

    // Regression pin: `spent` must include "Recent transactions:" and the
    // separator before it before the row loop starts. At this budget, the
    // old accounting kept a second row it should not have, and the render it
    // produced landed past the budget by exactly the header's length.
    @Test func transactionRowsNeverPushTheRenderPastBudget() {
        let recent = (0..<5).map {
            ContextBundle.Money.Transaction(
                merchant: "Merchant \($0)", category: "Food",
                amount: -12.5, date: Date(timeIntervalSince1970: 1_756_000_000)
            )
        }
        let bundle = ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(income: 8000, expenses: 5000, savingsRate: nil,
                                       netWorth: nil, recent: recent)
        )
        let lines = bundle.promptLines(for: .offDevice, budget: 120)
        #expect(lines.contains("Merchant 0"))
        #expect(!lines.contains("Merchant 1"))
        #expect(lines.count <= 120)
    }

    // The priority order under pressure: transactions and the digest's own
    // history are what shrink first; the money summary and sector score
    // must still be present, even against a real, multi-day digest.
    @Test func theSummaryLinesSurviveATightBudgetEvenWithARealDigest() throws {
        let bundle = ContextBundle(
            digest: try fortnightDigest(),
            money: ContextBundle.Money(income: 8000, expenses: 5000, savingsRate: nil,
                                       netWorth: nil, recent: []),
            sectors: [ContextBundle.Sector(name: "Body", score: 7, delta: 1)]
        )
        let lines = bundle.promptLines(for: .offDevice, budget: 700)
        #expect(lines.contains("income 8000"))
        #expect(lines.contains("Body 7 (+1)"))
    }
}
