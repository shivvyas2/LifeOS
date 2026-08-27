import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// Whoop used to assign its columns unconditionally, which made it the winner
/// by write order rather than by rule. Now it goes through the same arbiter as
/// everything else.
@Suite @MainActor struct WhoopArbitrationTests {

    private let day = Calendar.current.startOfDay(for: .now)

    private func makeStore() throws -> (MetricsStore, ModelContext) {
        let context = ModelContext(try LifeOSContainer.make(inMemory: true))
        return (MetricsStore(context: context), context)
    }

    private func derivation(
        _ store: MetricsStore, _ context: ModelContext,
        primary: MetricSource = .whoop
    ) -> WhoopDerivation {
        WhoopDerivation(
            store: store, archive: WhoopArchive(context: context),
            ranking: SourceRanking(primaryWearable: primary)
        )
    }

    private func recovery(restingHR: Double? = nil, recovery: Double? = nil) -> WhoopRecoverySample {
        WhoopRecoverySample(
            date: day, recoveryPercentage: recovery, restingHeartRate: restingHR,
            hrvMilliseconds: nil, spo2Percentage: nil, skinTempCelsius: nil, isCalibrating: nil
        )
    }

    /// The headline rule, now expressed as a rank rather than as write order.
    @Test func whoopOwnsTheMetricsItMeasures() throws {
        let (store, context) = try makeStore()
        try store.upsert(date: day) { row in
            row.restingHR = 55
            row.setSource(HealthMetric.restingHR.rawValue, MetricSource.appleHealth.rawValue)
        }

        try derivation(store, context).derive(recoveries: [recovery(restingHR: 52)])

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 52)
        #expect(row.source(HealthMetric.restingHR.rawValue) == MetricSource.whoop.rawValue)
    }

    /// The phone counts exercise minutes better than a strap infers them, so
    /// Whoop fills a gap there rather than overwriting. This preserves the
    /// outcome the old write order produced, where the Health sync ran second.
    @Test func whoopDoesNotOverwriteThePhonesExerciseMinutes() throws {
        let (store, context) = try makeStore()
        try store.upsert(date: day) { row in
            row.exerciseMinutes = 31
            row.setSource(HealthMetric.exerciseMinutes.rawValue, MetricSource.appleHealth.rawValue)
        }

        let workout = WhoopWorkoutSample(
            externalID: "w1", start: day.addingTimeInterval(3600),
            end: day.addingTimeInterval(7440), sportName: "Running", sportID: nil,
            strain: nil, energyKcal: nil, averageHR: nil, maxHR: nil,
            percentRecorded: nil, distanceMeters: nil,
            altitudeGainMeters: nil, altitudeChangeMeters: nil
        )
        try derivation(store, context).derive(workouts: [workout])

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.exerciseMinutes == 31)
    }

    /// A typed weight is not replaced by the figure someone once entered in the
    /// Whoop app.
    @Test func whoopDoesNotOverwriteATypedWeight() throws {
        let (store, context) = try makeStore()
        try store.upsert(date: day) { row in
            row.weightKg = 74.2
            row.setSource(HealthMetric.weightKg.rawValue, MetricSource.manual.rawValue)
        }

        let body = WhoopBodySample(heightMeters: nil, weightKilograms: 80.0, maxHeartRate: nil)
        try derivation(store, context).derive(body: (sample: body, date: day))

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.weightKg == 74.2)
    }

    /// Whoop's own scored columns have no second writer, so they are assigned
    /// directly and must not acquire provenance they do not need.
    @Test func whoopOnlyColumnsAreWrittenDirectly() throws {
        let (store, context) = try makeStore()
        try derivation(store, context).derive(recoveries: [recovery(recovery: 66)])

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.whoopRecoveryPct == 66)
        #expect(row.source("whoopRecoveryPct") == nil)
    }

    /// When the user names Fitbit as primary, Whoop drops to secondary and
    /// stops overwriting the metrics the chosen strap reports.
    @Test func whoopYieldsToTheChosenStrap() throws {
        let (store, context) = try makeStore()
        try store.upsert(date: day) { row in
            row.restingHR = 48
            row.setSource(HealthMetric.restingHR.rawValue, MetricSource.fitbit.rawValue)
        }

        try derivation(store, context, primary: .fitbit)
            .derive(recoveries: [recovery(restingHR: 52)])

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 48)
    }
}
