import Testing
import Foundation
import SwiftData
@testable import Integrations
@testable import Persistence

/// The fill rules applied to a real row, which is where a mapping mistake would
/// actually show up: `HealthFill` can be perfect and still write HRV into the
/// resting-HR column.
@Suite @MainActor struct HealthApplyTests {

    private func store() throws -> MetricsStore {
        MetricsStore(context: ModelContext(try LifeOSContainer.make(inMemory: true)))
    }

    private let day = Calendar.current.startOfDay(for: .now)

    @Test func healthFillsAnEmptyDayAcrossEveryColumn() throws {
        let store = try store()
        let health = HealthDay(date: day, values: [
            .steps: 9770,
            .activeEnergyKcal: 480,
            .exerciseMinutes: 31,
            .weightKg: 74.2,
            .waterML: 250,
            .restingHR: 55,
            .hrvMs: 91,
            .spo2Percentage: 97,
            .respiratoryRate: 14.2,
            .sleepMinutes: 402,
        ])

        try HealthApply.write(health, into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.steps == 9770)
        #expect(row.activeEnergyKcal == 480)
        #expect(row.exerciseMinutes == 31)
        #expect(row.weightKg == 74.2)
        #expect(row.waterML == 250)
        #expect(row.restingHR == 55)
        #expect(row.hrvMs == 91)
        #expect(row.spo2Percentage == 97)
        #expect(row.respiratoryRate == 14.2)
        #expect(row.sleepMinutes == 402)
    }

    /// The headline rule: a night on the strap is not overwritten by the phone's
    /// guess at the same night.
    @Test func whoopValuesSurviveAHealthSync() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.restingHR = 52
            row.hrvMs = 88
            row.sleepMinutes = 431
            // Attributed, because Whoop attributes its writes now. An
            // unattributed value ranks below every identified source, which is
            // what re-attributes legacy rows on the first sync after upgrade.
            for metric in [HealthMetric.restingHR, .hrvMs, .sleepMinutes] {
                row.setSource(metric.rawValue, MetricSource.whoop.rawValue)
            }
        }

        try HealthApply.write(
            HealthDay(date: day, values: [.restingHR: 55, .hrvMs: 91, .sleepMinutes: 402, .steps: 9770]),
            into: store
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 52)
        #expect(row.hrvMs == 88)
        #expect(row.sleepMinutes == 431)
        // And the field Whoop never reports still lands.
        #expect(row.steps == 9770)
    }

    /// Steps climb through the day, so a later sync has to be allowed to
    /// correct an earlier one.
    @Test func aLaterSyncCorrectsTheStepCount() throws {
        let store = try store()
        try HealthApply.write(HealthDay(date: day, values: [.steps: 4000]), into: store)
        try HealthApply.write(HealthDay(date: day, values: [.steps: 9770]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.steps == 9770)
    }

    /// A day Health knows nothing about must not blank the day Whoop filled.
    @Test func anEmptyHealthDayChangesNothing() throws {
        let store = try store()
        try store.upsert(date: day) { $0.restingHR = 52 }

        try HealthApply.write(HealthDay(date: day, values: [:]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 52)
    }

    /// Steps are a count. Storing 9770.6 and rendering it as "9770.6 steps"
    /// would be its own small embarrassment.
    @Test func countsAreStoredAsIntegers() throws {
        let store = try store()
        try HealthApply.write(
            HealthDay(date: day, values: [.steps: 9770.6, .exerciseMinutes: 31.4, .sleepMinutes: 402.7]),
            into: store
        )

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.steps == 9771)
        #expect(row.exerciseMinutes == 31)
        #expect(row.sleepMinutes == 403)
    }

    /// The write records who wrote it, or the next sync cannot arbitrate.
    @Test func aHealthWriteRecordsItsProvenance() throws {
        let store = try store()
        try HealthApply.write(HealthDay(date: day, values: [.steps: 9770, .restingHR: 55]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.source(HealthMetric.steps.rawValue) == MetricSource.appleHealth.rawValue)
        #expect(row.source(HealthMetric.restingHR.rawValue) == MetricSource.appleHealth.rawValue)
    }

    /// A value Whoop wrote and attributed is not replaced by the phone.
    @Test func anAttributedWhoopValueSurvivesAHealthSync() throws {
        let store = try store()
        try store.upsert(date: day) { row in
            row.restingHR = 52
            row.setSource(HealthMetric.restingHR.rawValue, MetricSource.whoop.rawValue)
        }

        try HealthApply.write(HealthDay(date: day, values: [.restingHR: 55]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.restingHR == 52)
        #expect(row.source(HealthMetric.restingHR.rawValue) == MetricSource.whoop.rawValue)
    }

    /// The migration trap, at the level where it would actually bite: a weight
    /// typed before provenance existed carries no attribution, and a sync must
    /// still leave it alone.
    @Test func anUnattributedWeightIsNotReplacedByASync() throws {
        let store = try store()
        try store.upsert(date: day) { row in row.weightKg = 74.2 }

        try HealthApply.write(HealthDay(date: day, values: [.weightKg: 75.0]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.weightKg == 74.2)
    }

    /// Metrics in the extras bag get provenance too, not just the named columns.
    @Test func theLongTailIsAttributedAsWell() throws {
        let store = try store()
        try HealthApply.write(HealthDay(date: day, values: [.vo2Max: 48.2]), into: store)

        let row = try #require(try store.metrics(from: day, to: day).first)
        #expect(row.extra(HealthMetric.vo2Max.rawValue) == 48.2)
        #expect(row.source(HealthMetric.vo2Max.rawValue) == MetricSource.appleHealth.rawValue)
    }
}
