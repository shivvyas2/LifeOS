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
        #expect(lines.contains("Food -37.50 (3)"))
        #expect(lines.contains("Body 7 (+1)"))
        #expect(lines.contains("Money unscored"))
        #expect(lines.contains("Shiv"))
    }

    // The privacy rule for a paid model: it may learn how spending splits
    // across categories, never which merchant took which amount on which
    // day. Merchant names, per-row amounts and dates are the identifying
    // detail, and a category total carries none of them.
    @Test func theOffDeviceRenderNeverCarriesAMerchantRowOrDate() {
        let recent = [
            ContextBundle.Money.Transaction(merchant: "Blue Bottle", category: "Food",
                                            amount: -6.75, date: Date(timeIntervalSince1970: 1_756_000_000)),
            ContextBundle.Money.Transaction(merchant: "Blue Bottle", category: "Food",
                                            amount: -6.75, date: Date(timeIntervalSince1970: 1_756_086_400)),
            ContextBundle.Money.Transaction(merchant: "MTA", category: "Transport",
                                            amount: -2.90, date: Date(timeIntervalSince1970: 1_756_172_800)),
            ContextBundle.Money.Transaction(merchant: "Payroll", category: nil,
                                            amount: 3_200, date: Date(timeIntervalSince1970: 1_756_259_200)),
        ]
        let bundle = ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(income: 3_200, expenses: 16.40, savingsRate: nil,
                                       netWorth: nil, recent: recent)
        )
        let lines = bundle.promptLines(for: .offDevice)
        #expect(!lines.contains("Blue Bottle"))
        #expect(!lines.contains("MTA"))
        #expect(!lines.contains("Payroll"))
        #expect(!lines.contains("6.75"))
        #expect(!lines.contains("2.90"))
        #expect(!lines.contains("Aug "))
        #expect(lines.contains("3 purchases"))
        #expect(lines.contains("Food -13.50 (2)"))
        #expect(!lines.contains("Transport")) // a lone purchase is a row under another name
        #expect(!lines.contains("3200.00"))   // income never enters the breakdown
    }

    // A category with one transaction is a per-row amount with a different
    // label, so it folds into "Other" rather than being printed on its own.
    @Test func singletonCategoriesFoldIntoOther() {
        let recent = [
            ContextBundle.Money.Transaction(merchant: "A", category: "Food", amount: -10, date: .init(timeIntervalSince1970: 1_756_000_000)),
            ContextBundle.Money.Transaction(merchant: "B", category: "Food", amount: -20, date: .init(timeIntervalSince1970: 1_756_000_000)),
            ContextBundle.Money.Transaction(merchant: "C", category: "Transport", amount: -5, date: .init(timeIntervalSince1970: 1_756_000_000)),
            ContextBundle.Money.Transaction(merchant: "D", category: "Pets", amount: -7, date: .init(timeIntervalSince1970: 1_756_000_000)),
        ]
        let bundle = ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(income: 0, expenses: 42, savingsRate: nil, netWorth: nil, recent: recent)
        )
        let lines = bundle.promptLines(for: .offDevice)
        #expect(lines.contains("Food -30.00 (2)"))
        #expect(lines.contains("Other -12.00 (2)"))
        #expect(!lines.contains("Transport"))
        #expect(!lines.contains("Pets"))
    }

    // The on-device window is small; a spending breakdown would drown the digest.
    @Test func theOnDeviceRenderSkipsSpendingDetail() {
        let lines = bundle().promptLines(for: .onDevice)
        #expect(!lines.contains("Food -37.50"))
        #expect(!lines.contains("Merchant 0"))
        #expect(lines.contains("Body 7 (+1)"))
    }

    // Truncation drops the spending breakdown first; sectors and the money
    // summary survive because they are the cheapest, densest lines.
    @Test func aTightBudgetDropsSpendingDetailBeforeSummary() {
        let lines = bundle(transactions: 200).promptLines(for: .offDevice, budget: 120)
        #expect(!lines.contains("Food"))
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

    // Regression pin: `spent` must include the header and the separator
    // before it before the category loop starts, otherwise every render that
    // keeps at least one category overshoots `budget` by the header's length.
    @Test func categoryRowsNeverPushTheRenderPastBudget() {
        let recent = ["Food", "Food", "Transport", "Transport", "Rent", "Rent", "Pets", "Pets"].map {
            ContextBundle.Money.Transaction(
                merchant: "Merchant", category: $0,
                amount: -12.5, date: Date(timeIntervalSince1970: 1_756_000_000)
            )
        }
        let bundle = ContextBundle(
            digest: MetricsDigest.from(metrics: [], sleeps: [], workouts: []),
            money: ContextBundle.Money(income: 8000, expenses: 5000, savingsRate: nil,
                                       netWorth: nil, recent: recent)
        )
        // Equal totals sort by name, so the rows run Food, Pets, Rent,
        // Transport; 120 characters holds the first two exactly.
        let lines = bundle.promptLines(for: .offDevice, budget: 120)
        #expect(lines.contains("Food -25.00 (2)"))
        #expect(lines.contains("Pets -25.00 (2)"))
        #expect(!lines.contains("Rent"))
        #expect(lines.count <= 120)
    }

    // The priority order under pressure: transactions and the digest's own
    // history are what shrink first; the money summary and sector score
    // must still be present, even against a real, multi-day digest. The
    // length assertion is what actually pins this: the digest's own default
    // budget (6000) comfortably fits a fortnight in full, so a render that
    // forgot to forward the bundle's own tighter budget down to the digest
    // would still contain both lines here -- it would just also blow past
    // 700, which only the length check would catch.
    @Test func theSummaryLinesSurviveAndTheTotalStaysWithinBudgetWithARealDigest() throws {
        let bundle = ContextBundle(
            digest: try fortnightDigest(),
            money: ContextBundle.Money(income: 8000, expenses: 5000, savingsRate: nil,
                                       netWorth: nil, recent: []),
            sectors: [ContextBundle.Sector(name: "Body", score: 7, delta: 1)]
        )
        let lines = bundle.promptLines(for: .offDevice, budget: 700)
        #expect(lines.contains("income 8000"))
        #expect(lines.contains("Body 7 (+1)"))
        #expect(lines.count <= 700)
    }

    // The documented floor: MetricsDigest never truncates below one day, so
    // a budget small enough to collapse the digest's own allowance to
    // (near-)zero still gets a full day of health data back rather than
    // nothing -- over budget by at most that one irreducible block, not by
    // an unbounded amount. This is now a stated property of
    // `promptLines(for:budget:)`'s doc comment, so it gets a test rather
    // than staying an untested edge.
    @Test func aCollapsedDigestBudgetStillEmitsOneDayRatherThanNothing() throws {
        let digest = try singleDayDigest()
        // With only one day in the digest to begin with, an uncapped render
        // IS the one irreducible day block: there is nothing left to drop.
        // That makes it the ceiling any budget can be overrun by here.
        let oneDayBlock = digest.promptLines(for: .offDevice, budget: 100_000)
        let bundle = ContextBundle(digest: digest)

        let lines = bundle.promptLines(for: .offDevice, budget: 1)

        #expect(!lines.isEmpty)
        #expect(lines.contains("recovery 62%"))
        #expect(lines.count > 1)                  // the floor genuinely overruns this budget
        #expect(lines.count <= oneDayBlock.count) // but never by more than one day block
    }

    private func singleDayDigest() throws -> MetricsDigest {
        let container = try LifeOSContainer.make(inMemory: true)
        let store = MetricsStore(context: ModelContext(container))
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))
        try store.upsert(date: day) {
            $0.whoopRecoveryPct = 62
            $0.steps = 8_000
        }
        return MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )
    }
}
