import Testing
@testable import Integrations

/// The rank table is the whole merge rule. It is pinned here because every
/// failure it can have is silent: a number that flips between syncs looks to
/// the user like their body changed, not like two sources disagreeing.
@Suite struct MetricSourceTests {

    private let whoopFirst = SourceRanking(primaryWearable: .whoop)
    private let fitbitFirst = SourceRanking(primaryWearable: .fitbit)

    /// A typed number outranks every sync, on every metric.
    @Test func manualOutranksEverything() {
        for metric in HealthMetric.allCases {
            let manual = whoopFirst.rank(.manual, for: metric)
            #expect(manual > whoopFirst.rank(.whoop, for: metric))
            #expect(manual > whoopFirst.rank(.fitbit, for: metric))
            #expect(manual > whoopFirst.rank(.appleHealth, for: metric))
        }
    }

    /// A metric a strap measures: the chosen strap outranks the other, and both
    /// outrank the phone.
    @Test func theChosenStrapOwnsAMetricItMeasures() {
        #expect(whoopFirst.rank(.whoop, for: .hrvMs) > whoopFirst.rank(.fitbit, for: .hrvMs))
        #expect(whoopFirst.rank(.fitbit, for: .hrvMs) > whoopFirst.rank(.appleHealth, for: .hrvMs))

        #expect(fitbitFirst.rank(.fitbit, for: .hrvMs) > fitbitFirst.rank(.whoop, for: .hrvMs))
        #expect(fitbitFirst.rank(.whoop, for: .hrvMs) > fitbitFirst.rank(.appleHealth, for: .hrvMs))
    }

    /// A metric no strap measures: the phone counts it, so the phone is the
    /// authority and a strap only fills a gap.
    @Test func thePhoneOwnsWhatOnlyThePhoneCounts() {
        for metric in [HealthMetric.steps, .activeEnergyKcal, .exerciseMinutes, .distanceKm] {
            #expect(whoopFirst.rank(.appleHealth, for: metric) > whoopFirst.rank(.whoop, for: metric))
        }
    }

    /// Weight and water are typed, so the phone is not the authority for them
    /// either, and a strap's reading beats a passive one.
    @Test func typedMetricsDoNotMakeThePhoneTheAuthority() {
        for metric in [HealthMetric.weightKg, .waterML] {
            #expect(!metric.healthIsAuthoritative)
            #expect(whoopFirst.rank(.whoop, for: metric) > whoopFirst.rank(.appleHealth, for: metric))
        }
    }

    /// A row written before provenance existed ranks below every identified
    /// source, so the first sync after upgrade attributes it correctly.
    @Test func anUnattributedValueRanksLowest() {
        for metric in HealthMetric.allCases {
            #expect(whoopFirst.rank(nil, for: metric) == 0)
            #expect(whoopFirst.rank(.appleHealth, for: metric) > 0)
        }
    }

    /// The five Whoop measures from a strap worn all night must stay claimed,
    /// or a phone estimate silently replaces a measurement.
    @Test func theStrapMeasuredMetricsStayClaimed() {
        for metric in [HealthMetric.restingHR, .hrvMs, .spo2Percentage,
                       .respiratoryRate, .sleepMinutes] {
            #expect(metric.claimedByWearable, "\(metric.rawValue) lost its guard")
        }
    }

    /// Exactly the two a person can type in this app.
    @Test func onlyWeightAndWaterAreTyped() {
        let typed = HealthMetric.allCases.filter(\.acceptsManualEntry)
        #expect(Set(typed) == Set([.weightKg, .waterML]))
    }
}
