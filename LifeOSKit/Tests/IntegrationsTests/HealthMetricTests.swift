import Testing
@testable import Integrations

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
