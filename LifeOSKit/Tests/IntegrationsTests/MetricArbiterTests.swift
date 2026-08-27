import Testing
@testable import Integrations

/// Who wins when two sources have a number for the same day.
@Suite struct MetricArbiterTests {

    private let whoopFirst = SourceRanking(primaryWearable: .whoop)
    private let fitbitFirst = SourceRanking(primaryWearable: .fitbit)

    private func resolve(
        _ metric: HealthMetric,
        existing: Double?, from existingSource: MetricSource?,
        incoming: Double?, from incomingSource: MetricSource,
        ranking: SourceRanking? = nil
    ) -> (value: Double?, source: MetricSource?) {
        MetricArbiter.resolve(
            metric: metric,
            existing: existing, existingSource: existingSource,
            incoming: incoming, incomingSource: incomingSource,
            ranking: ranking ?? whoopFirst
        )
    }

    // MARK: - The rule that destroys data if it is wrong

    /// A source having no reading is not evidence of zero. Blanking a real
    /// value because a query came back empty is the one failure here that
    /// destroys data rather than merely showing the wrong number.
    @Test func aMissingReadingNeverClearsAnExistingValue() {
        for metric in HealthMetric.allCases {
            let kept = resolve(metric, existing: 42, from: .whoop, incoming: nil, from: .appleHealth)
            #expect(kept.value == 42)
            #expect(kept.source == .whoop)

            let empty = resolve(metric, existing: nil, from: nil, incoming: nil, from: .appleHealth)
            #expect(empty.value == nil)
            #expect(empty.source == nil)
        }
    }

    // MARK: - Preserved from HealthFill

    @Test func healthDoesNotOverwriteAWhoopValue() {
        #expect(resolve(.restingHR, existing: 52, from: .whoop, incoming: 55, from: .appleHealth).value == 52)
        #expect(resolve(.hrvMs, existing: 88, from: .whoop, incoming: 91, from: .appleHealth).value == 88)
        #expect(resolve(.sleepMinutes, existing: 431, from: .whoop, incoming: 402, from: .appleHealth).value == 431)
    }

    @Test func healthFillsAWhoopGap() {
        let filled = resolve(.restingHR, existing: nil, from: nil, incoming: 55, from: .appleHealth)
        #expect(filled.value == 55)
        #expect(filled.source == .appleHealth)
    }

    /// Equal rank overwrites. This is what lets the afternoon sync correct the
    /// morning's count, and it is the entire job the old `healthIsTheSource`
    /// case did.
    @Test func healthOverwritesItsOwnPassivelyMeasuredCounts() {
        #expect(resolve(.steps, existing: 4000, from: .appleHealth, incoming: 9770, from: .appleHealth).value == 9770)
        #expect(resolve(.activeEnergyKcal, existing: 210, from: .appleHealth, incoming: 480, from: .appleHealth).value == 480)
        #expect(resolve(.exerciseMinutes, existing: 12, from: .appleHealth, incoming: 31, from: .appleHealth).value == 31)
    }

    @Test func aHandEnteredValueSurvivesTheSync() {
        #expect(resolve(.waterML, existing: 500, from: .manual, incoming: 250, from: .appleHealth).value == 500)
        #expect(resolve(.weightKg, existing: 74.2, from: .manual, incoming: 75.0, from: .appleHealth).value == 74.2)
        #expect(resolve(.weightKg, existing: 74.2, from: .manual, incoming: 75.0, from: .whoop).value == 74.2)
    }

    // MARK: - The change made on purpose

    /// Today a Health-written weight is frozen by `fillGapsOnly` and can never
    /// be corrected by a later Health reading. Equal rank fixes that, while a
    /// typed weight stays protected above.
    @Test func healthCorrectsAWeightItWroteItself() {
        let corrected = resolve(.weightKg, existing: 74.2, from: .appleHealth, incoming: 75.0, from: .appleHealth)
        #expect(corrected.value == 75.0)
        #expect(corrected.source == .appleHealth)
    }

    // MARK: - Two straps

    @Test func theChosenStrapOverwritesTheOther() {
        #expect(resolve(.sleepMinutes, existing: 431, from: .whoop,
                        incoming: 402, from: .fitbit, ranking: fitbitFirst).value == 402)
        #expect(resolve(.sleepMinutes, existing: 402, from: .fitbit,
                        incoming: 431, from: .whoop, ranking: fitbitFirst).value == 402)
    }

    @Test func theSecondaryStrapStillFillsAGap() {
        let filled = resolve(.hrvMs, existing: nil, from: nil, incoming: 62, from: .fitbit)
        #expect(filled.value == 62)
        #expect(filled.source == .fitbit)
    }

    // MARK: - The migration trap

    /// A row written before provenance existed is overwritten by any
    /// identified source, which re-attributes it correctly on the first sync.
    @Test func anUnattributedValueYieldsToAnIdentifiedOne() {
        let taken = resolve(.steps, existing: 4000, from: nil, incoming: 9770, from: .appleHealth)
        #expect(taken.value == 9770)
        #expect(taken.source == .appleHealth)
    }

    /// But a weight or water figure the user typed before this shipped is also
    /// unattributed, and must not be silently replaced. This is the one case
    /// where skipping the special handling destroys real user data.
    @Test func anUnattributedTypedValueIsTreatedAsTyped() {
        #expect(resolve(.weightKg, existing: 74.2, from: nil, incoming: 75.0, from: .appleHealth).value == 74.2)
        #expect(resolve(.waterML, existing: 500, from: nil, incoming: 250, from: .appleHealth).value == 500)
        #expect(MetricSource.legacy(for: .weightKg) == .manual)
        #expect(MetricSource.legacy(for: .waterML) == .manual)
        #expect(MetricSource.legacy(for: .steps) == nil)
    }
}
