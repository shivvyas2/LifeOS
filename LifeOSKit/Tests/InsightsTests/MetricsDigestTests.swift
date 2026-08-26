import Testing
import Foundation
import SwiftData
import Persistence
@testable import Insights

@Suite @MainActor struct MetricsDigestTests {

    private func makeStore() throws -> MetricsStore {
        let container = try LifeOSContainer.make(inMemory: true)
        return MetricsStore(context: ModelContext(container))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_770_000_000))

    @Test func aDigestCarriesOneEntryPerDay() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 8_000 }

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.days.count == 1)
        #expect(digest.days[0].steps == 8_000)
    }

    /// A missing value and a zero must never become the same thing, which is
    /// the rule `DailyMetrics` is built around. The digest inherits it.
    @Test func aMissingMetricStaysNilRatherThanBecomingZero() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 8_000 }

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.days[0].steps == 8_000)
        #expect(digest.days[0].sleepMinutes == nil)
        #expect(digest.days[0].recoveryPct == nil)
    }

    @Test func averagesIgnoreDaysWithNoReading() throws {
        let store = try makeStore()
        let second = day.addingTimeInterval(86_400)
        try store.upsert(date: day) { $0.steps = 10_000 }
        try store.upsert(date: second) { $0.weightKg = 78 }   // no steps

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: second), sleeps: [], workouts: []
        )

        // 10_000 over one contributing day, not 5_000 over two.
        #expect(digest.averages.steps == 10_000)
    }

    @Test func averagesAreNilWhenNothingContributes() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.weightKg = 78 }

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.averages.steps == nil)
    }

    /// The privacy rule, scoped to where it bites. HRV, SpO2, skin temperature
    /// and respiratory rate are fine on-device, where nothing leaves the phone.
    /// They must not appear in a render destined for a provider.
    ///
    /// Revised 2026-08-26. The blanket version of this test predated any
    /// off-device path and blocked the on-device coach from data already on
    /// the device.
    @Test func anOffDeviceRenderCarriesNoRawWhoopSeries() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.steps = 8_000
            $0.whoopRecoveryPct = 62
            $0.hrvMs = 41.2
            $0.spo2Percentage = 97.5
            $0.skinTempCelsius = 33.4
            $0.respiratoryRate = 14.2
        }
        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        let offDevice = digest.promptLines(for: .offDevice)

        #expect(offDevice.contains("62"))              // the aggregate is wanted
        #expect(offDevice.contains("41.2") == false)   // HRV series is not
        #expect(offDevice.contains("97.5") == false)
        #expect(offDevice.contains("33.4") == false)
        #expect(offDevice.contains("14.2") == false)
    }

    @Test func anOnDeviceRenderCarriesTheSeries() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.hrvMs = 41.2
            $0.spo2Percentage = 97.5
        }
        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.promptLines(for: .onDevice).contains("41.2"))
        #expect(digest.promptLines.contains("97.5"))   // the property defaults to on-device
    }

    @Test func aDayCarriesTheWiderWhoopSurface() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.whoopRecoveryPct = 51
            $0.hrvMs = 38
            $0.restingHR = 61
            $0.spo2Percentage = 95
            $0.skinTempCelsius = 33.7
            $0.whoopRecoveryIsCalibrating = true
        }

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.days[0].hrvMs == 38)
        #expect(digest.days[0].restingHR == 61)
        #expect(digest.days[0].spo2Pct == 95)
        #expect(digest.days[0].skinTempCelsius == 33.7)
        #expect(digest.days[0].recoveryIsCalibrating == true)
    }

    @Test func nightSleepAndNapsStaySeparate() throws {
        let store = try makeStore()
        try store.upsert(date: day) { _ in }
        let night = SleepRecord(externalID: "n", start: day.addingTimeInterval(-3_600),
                                end: day.addingTimeInterval(21_600), attributedDate: day)
        night.remMinutes = 62
        night.swsMinutes = 80
        night.isNap = false
        let nap = SleepRecord(externalID: "p", start: day.addingTimeInterval(50_000),
                              end: day.addingTimeInterval(52_280), attributedDate: day)
        nap.isNap = true

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day),
            sleeps: [night, nap], workouts: []
        )

        #expect(digest.days[0].remMinutes == 62)
        #expect(digest.days[0].swsMinutes == 80)
        #expect(digest.days[0].napMinutes == 38)   // 2280s
    }

    @Test func aDayWithNoNapReportsNilRatherThanZero() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 100 }

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        )

        #expect(digest.days[0].napMinutes == nil)
    }

    @Test func workoutsAttachToTheDayTheyStarted() throws {
        let store = try makeStore()
        let second = day.addingTimeInterval(86_400)
        try store.upsert(date: day) { _ in }
        try store.upsert(date: second) { _ in }
        let record = WorkoutRecord(externalID: "w", start: second.addingTimeInterval(3_600),
                                   durationMinutes: 92, activityName: "cycling")
        record.strain = 11.4
        record.zoneThreeMinutes = 20
        record.zoneFourMinutes = 15
        record.zoneFiveMinutes = 7

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: second), sleeps: [], workouts: [record]
        )

        #expect(digest.days[0].workouts.isEmpty)
        #expect(digest.days[1].workouts.count == 1)
        #expect(digest.days[1].workouts[0].name == "cycling")
        #expect(digest.days[1].workouts[0].zoneMinutes == [0, 0, 0, 20, 15, 7])
    }

    @Test func theRenderCarriesEveryPopulatedFieldAndOmitsTheRest() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.whoopRecoveryPct = 51
            $0.hrvMs = 38
            $0.whoopDayStrain = 12.1
            // steps deliberately absent
        }

        let text = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        ).promptLines

        #expect(text.contains("recovery 51%"))
        #expect(text.contains("hrv 38ms"))
        #expect(text.contains("strain 12.1"))
        #expect(text.contains("steps") == false)   // absent, not "steps 0"
    }

    @Test func aCalibratingRecoveryIsMarkedInTheRender() throws {
        let store = try makeStore()
        try store.upsert(date: day) {
            $0.whoopRecoveryPct = 44
            $0.whoopRecoveryIsCalibrating = true
        }

        let text = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: []
        ).promptLines

        #expect(text.contains("recovery 44% (calibrating)"))
    }

    @Test func aDeltaAppearsOnlyWhereAnAverageExists() throws {
        let store = try makeStore()
        let second = day.addingTimeInterval(86_400)
        try store.upsert(date: day) { $0.whoopRecoveryPct = 60 }
        try store.upsert(date: second) { $0.whoopRecoveryPct = 40 }

        let text = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: second), sleeps: [], workouts: []
        ).promptLines

        #expect(text.contains("2-day baseline"))
        #expect(text.contains("recovery 60% (+10)"))
        #expect(text.contains("recovery 40% (-10)"))
    }

    @Test func aWorkoutRendersItsHighZoneTime() throws {
        let store = try makeStore()
        try store.upsert(date: day) { $0.steps = 100 }
        let record = WorkoutRecord(externalID: "w", start: day.addingTimeInterval(3_600),
                                   durationMinutes: 92, activityName: "cycling")
        record.strain = 11.4
        record.averageHR = 141
        record.zoneThreeMinutes = 20
        record.zoneFourMinutes = 15
        record.zoneFiveMinutes = 7

        let text = MetricsDigest.from(
            metrics: try store.metrics(from: day, to: day), sleeps: [], workouts: [record]
        ).promptLines

        #expect(text.contains("workout: cycling 92m"))
        #expect(text.contains("strain 11.4"))
        #expect(text.contains("zone 3+ 42m"))
    }

    @Test func theRenderDropsWholeDaysOldestFirstToFitTheBudget() throws {
        let store = try makeStore()
        var dates: [Date] = []
        for offset in 0..<14 {
            let d = day.addingTimeInterval(Double(offset) * 86_400)
            dates.append(d)
            try store.upsert(date: d) {
                $0.whoopRecoveryPct = 50 + Double(offset)
                $0.steps = 8_000
            }
        }
        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: dates.first!, to: dates.last!),
            sleeps: [], workouts: []
        )

        let full = digest.promptLines(for: .onDevice, budget: 100_000)
        let squeezed = digest.promptLines(for: .onDevice, budget: 300)

        #expect(squeezed.count <= 300)
        #expect(squeezed.count < full.count)
        // The newest day survives; the oldest is what goes.
        #expect(squeezed.contains("recovery 63%"))
        #expect(squeezed.contains("recovery 50%") == false)
    }

    /// The regression pin. A fully populated fortnight must fit the real budget.
    @Test func aFullyPopulatedFortnightFitsTheBudget() throws {
        let store = try makeStore()
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

        let digest = MetricsDigest.from(
            metrics: try store.metrics(from: dates.first!, to: dates.last!),
            sleeps: sleeps, workouts: workouts
        )

        let text = digest.promptLines(for: .onDevice, budget: MetricsDigest.promptBudget)

        // Nothing was dropped: all fourteen days survive at the real budget.
        #expect(text.contains("rem 1h02m"))
        #expect(digest.days.count == 14)
        #expect(text.count <= MetricsDigest.promptBudget)
    }
}
