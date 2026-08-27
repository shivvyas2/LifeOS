import Testing
@testable import Integrations

/// Who wins when Apple Health and Whoop both have a number for the same day.
///
/// The rule is "Whoop wins, Health fills gaps", and it is worth pinning
/// because the failure mode is silent: a value that flips between syncs looks
/// to the user like their body changed, not like two sources disagreeing.
@Suite struct HealthFillTests {

    // MARK: - Shared with Whoop

    /// Whoop measures resting HR directly. If it has a number, Health does not
    /// get to overwrite it.
    @Test func healthDoesNotOverwriteAWhoopValue() {
        #expect(HealthFill.value(for: .restingHR, existing: 52, health: 55) == 52)
        #expect(HealthFill.value(for: .hrvMs, existing: 88, health: 91) == 88)
        #expect(HealthFill.value(for: .sleepMinutes, existing: 431, health: 402) == 431)
    }

    /// But a gap is a gap. No strap last night means Health's number is the
    /// only one there is.
    @Test func healthFillsAWhoopGap() {
        #expect(HealthFill.value(for: .restingHR, existing: nil, health: 55) == 55)
        #expect(HealthFill.value(for: .sleepMinutes, existing: nil, health: 402) == 402)
    }

    // MARK: - Health's own signals

    /// Whoop never reports steps or exercise minutes, and nobody types them in.
    /// Health is the only source, so its latest count is simply the truth, and
    /// it must be allowed to correct a number it reported earlier the same day.
    @Test func healthOverwritesItsOwnPassivelyMeasuredCounts() {
        #expect(HealthFill.value(for: .steps, existing: 4000, health: 9770) == 9770)
        #expect(HealthFill.value(for: .activeEnergyKcal, existing: 210, health: 480) == 480)
        #expect(HealthFill.value(for: .exerciseMinutes, existing: 12, health: 31) == 31)
    }

    /// Water and weight can be entered by hand in this app. A number the user
    /// typed is not something a background sync gets to replace.
    @Test func aHandEnteredValueSurvivesTheSync() {
        #expect(HealthFill.value(for: .waterML, existing: 500, health: 250) == 500)
        #expect(HealthFill.value(for: .weightKg, existing: 74.2, health: 75.0) == 74.2)
    }

    @Test func healthStillFillsWaterAndWeightWhenNothingWasEntered() {
        #expect(HealthFill.value(for: .waterML, existing: nil, health: 250) == 250)
        #expect(HealthFill.value(for: .weightKg, existing: nil, health: 75.0) == 75.0)
    }

    // MARK: - Nothing to write

    /// Health having no reading must never blank a value that is already there.
    /// This is the one that would quietly destroy data.
    @Test func aMissingHealthReadingNeverClearsAnExistingValue() {
        for metric in HealthMetric.allCases {
            #expect(HealthFill.value(for: metric, existing: 42, health: nil) == 42)
            #expect(HealthFill.value(for: metric, existing: nil, health: nil) == nil)
        }
    }

    /// Every metric has to declare which side of the rule it is on, or a new
    /// one added later silently inherits whatever the default happens to be.
    @Test func everyMetricDeclaresItsPrecedence() {
        let shared = HealthMetric.allCases.filter { $0.precedence == .fillGapsOnly }
        let owned = HealthMetric.allCases.filter { $0.precedence == .healthIsTheSource }

        #expect(shared.count + owned.count == HealthMetric.allCases.count)
        #expect(!shared.isEmpty)
        #expect(!owned.isEmpty)
        // The five Whoop also measures, plus the two a user can type.
        #expect(shared.contains(.restingHR))
        #expect(shared.contains(.waterML))
        #expect(owned.contains(.steps))
    }
}

@Suite struct HealthMetricVocabularyTests {

    /// Every metric must describe itself, or a row appears with a blank label.
    @Test func everyMetricHasATitleAndAGroup() {
        for metric in HealthMetric.allCases {
            #expect(!metric.title.isEmpty, "\(metric.rawValue) has no title")
            #expect(HealthMetric.Group.allCases.contains(metric.group))
        }
    }

    /// The raw values are the storage keys for everything without a column of
    /// its own, so a collision would silently overwrite one metric with
    /// another.
    @Test func rawValuesAreUnique() {
        #expect(Set(HealthMetric.allCases.map(\.rawValue)).count == HealthMetric.allCases.count)
    }

    /// Whoop owns the fields it measures from a strap worn all night, and a
    /// person types weight and water. Health must not overwrite either.
    @Test func whoopAndHandTypedFieldsStayFillGapsOnly() {
        let guarded: [HealthMetric] = [.restingHR, .hrvMs, .spo2Percentage,
                                       .respiratoryRate, .sleepMinutes, .weightKg, .waterML]
        for metric in guarded {
            #expect(metric.precedence == .fillGapsOnly, "\(metric.rawValue) lost its guard")
        }
    }

    /// Everything new arrived with no other writer, so the newest reading wins.
    @Test func newMetricsLetHealthBeTheSource() {
        for metric in [HealthMetric.vo2Max, .distanceKm, .deepSleepMinutes,
                       .bodyFatPercentage, .caffeineMg, .walkingSpeedKmh] {
            #expect(metric.precedence == .healthIsTheSource)
        }
    }

    @Test func formattingCarriesTheUnitAndTheRightPrecision() {
        #expect(HealthMetric.steps.formatted(9_770) == "9770")
        #expect(HealthMetric.distanceKm.formatted(7.42) == "7.4 km")
        #expect(HealthMetric.vo2Max.formatted(48.26) == "48.3 ml/kg·min")
        #expect(HealthMetric.wristTemperatureCelsius.formatted(36.428) == "36.43 °C")
    }

    /// Flow is an ordinal wearing a number's clothes, and HealthKit's raw
    /// values are not in an order anyone would guess.
    @Test func flowReadsAsWordsNotAsANumber() {
        #expect(HealthMetric.menstrualFlowLevel.formatted(2) == "Light")
        #expect(HealthMetric.menstrualFlowLevel.formatted(4) == "Heavy")
    }

    /// A sleep breakdown that is not part of the sleep group would be filed
    /// under the wrong panel and look like a missing metric.
    @Test func sleepStagesSitWithSleep() {
        for metric in [HealthMetric.deepSleepMinutes, .remSleepMinutes,
                       .coreSleepMinutes, .awakeMinutes, .timeInBedMinutes] {
            #expect(metric.group == .sleep)
        }
    }
}

@Suite struct CycleConsentTests {

    /// A permission sheet that asks every person for menstrual data is telling
    /// most of them the app has misread who they are. The first request must
    /// not contain it.
    @Test func theFirstRequestNeverAsksForCycleData() {
        #expect(HealthMetric.universal.allSatisfy { !$0.needsCycleConsent })
        #expect(HealthMetric.universal.contains(.steps))
        #expect(!HealthMetric.universal.contains(.menstrualFlowLevel))
    }

    @Test func cycleMetricsAreExactlyTheCycleGroup() {
        #expect(Set(HealthMetric.cycleOnly) == Set(HealthMetric.allCases.filter { $0.group == .cycle }))
        #expect(!HealthMetric.cycleOnly.isEmpty)
    }

    /// The two lists have to partition the vocabulary, or a metric is either
    /// never read or read without consent.
    @Test func universalAndCyclePartitionEveryMetric() {
        let combined = Set(HealthMetric.universal).union(HealthMetric.cycleOnly)
        #expect(combined == Set(HealthMetric.allCases))
        #expect(Set(HealthMetric.universal).isDisjoint(with: HealthMetric.cycleOnly))
    }

    /// Basal temperature is cycle data even though it reads like a vital, and
    /// filing it anywhere else would leak it past the switch.
    @Test func basalTemperatureIsGatedWithTheRest() {
        #expect(HealthMetric.basalBodyTemperatureCelsius.needsCycleConsent)
    }
}
