import Testing
import Foundation
@testable import Integrations

/// Decoding, pinned against Fitbit's published response shapes.
///
/// Wire format is the one thing that cannot be verified without a live token,
/// so it is pinned against fixtures instead. A silent decode failure here
/// looks exactly like a person having no data.
@Suite struct FitbitWireFormatTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func sleepDecodesItsStages() throws {
        let payload = try decode(FitbitSleepPayload.self, """
        {"sleep":[{"dateOfSleep":"2026-08-26","duration":28800000,"efficiency":91,
          "minutesAsleep":432,"minutesAwake":48,"timeInBed":480,"type":"stages",
          "levels":{"summary":{
            "deep":{"count":4,"minutes":78},
            "light":{"count":29,"minutes":244},
            "rem":{"count":6,"minutes":110},
            "wake":{"count":31,"minutes":48}}}}]}
        """)

        let night = try #require(payload.sleep.first)
        #expect(night.dateOfSleep == "2026-08-26")
        #expect(night.minutesAsleep == 432)
        #expect(night.timeInBed == 480)
        #expect(night.efficiency == 91)
        #expect(night.levels?.summary.deep?.minutes == 78)
        #expect(night.levels?.summary.rem?.minutes == 110)
        #expect(night.levels?.summary.light?.minutes == 244)
        #expect(night.levels?.summary.wake?.minutes == 48)
    }

    /// A classic log has no stages at all. It must decode, not throw, or one
    /// unstaged night takes the whole range down with it.
    @Test func aClassicSleepLogDecodesWithoutStages() throws {
        let payload = try decode(FitbitSleepPayload.self, """
        {"sleep":[{"dateOfSleep":"2026-08-25","duration":21600000,"efficiency":88,
          "minutesAsleep":360,"minutesAwake":20,"timeInBed":380,"type":"classic"}]}
        """)

        let night = try #require(payload.sleep.first)
        #expect(night.minutesAsleep == 360)
        #expect(night.levels == nil)
    }

    @Test func hrvDecodesTheDailyAndDeepValues() throws {
        let payload = try decode(FitbitHRVPayload.self, """
        {"hrv":[{"dateTime":"2026-08-26","value":{"dailyRmssd":34.2,"deepRmssd":41.6}}]}
        """)
        #expect(payload.hrv.first?.value.dailyRmssd == 34.2)
        #expect(payload.hrv.first?.value.deepRmssd == 41.6)
    }

    @Test func restingHeartRateDecodesOutOfTheActivitiesEnvelope() throws {
        let payload = try decode(FitbitHeartPayload.self, """
        {"activities-heart":[{"dateTime":"2026-08-26","value":{"restingHeartRate":54}}]}
        """)
        #expect(payload.days.first?.value.restingHeartRate == 54)
    }

    @Test func spo2AndBreathingAndTemperatureDecode() throws {
        let spo2 = try decode(FitbitSpO2Payload.self, """
        [{"dateTime":"2026-08-26","value":{"avg":95.7,"min":91.2,"max":98.4}}]
        """)
        #expect(spo2.first?.value.avg == 95.7)

        let breathing = try decode(FitbitBreathingPayload.self, """
        {"br":[{"dateTime":"2026-08-26","value":{"breathingRate":14.8}}]}
        """)
        #expect(breathing.br.first?.value.breathingRate == 14.8)

        let temperature = try decode(FitbitTemperaturePayload.self, """
        {"tempSkin":[{"dateTime":"2026-08-26","value":{"nightlyRelative":-0.3}}]}
        """)
        #expect(temperature.tempSkin.first?.value.nightlyRelative == -0.3)
    }

    /// Fitbit sends VO2 max either as a single number or as a range, depending
    /// on whether the user ran with GPS. Both arrive as a string.
    @Test func cardioFitnessDecodesANumberOrARange() throws {
        let payload = try decode(FitbitCardioPayload.self, """
        {"cardioScore":[{"dateTime":"2026-08-26","value":{"vo2Max":"46"}},
                        {"dateTime":"2026-08-25","value":{"vo2Max":"40-44"}}]}
        """)
        #expect(payload.cardioScore.first?.value.vo2Max == "46")
        #expect(payload.cardioScore.last?.value.vo2Max == "40-44")
    }

    /// A device with no such sensor returns an empty collection. Absence is
    /// normal and must decode to nothing, never to a zero and never to a throw.
    @Test func aSensorlessDeviceReturnsAnEmptyRange() throws {
        #expect(try decode(FitbitHRVPayload.self, #"{"hrv":[]}"#).hrv.isEmpty)
        #expect(try decode(FitbitSleepPayload.self, #"{"sleep":[]}"#).sleep.isEmpty)
        #expect(try decode(FitbitSpO2Payload.self, "[]").isEmpty)
    }

    /// The range caps are Fitbit's, and exceeding one is a 400 that names
    /// nothing useful.
    @Test func eachCollectionKnowsItsRangeCap() {
        #expect(FitbitCollection.sleep.maximumRangeDays == 100)
        #expect(FitbitCollection.restingHeartRate.maximumRangeDays == 365)
        for collection in [FitbitCollection.hrv, .spo2, .breathing,
                           .skinTemperature, .cardioFitness] {
            #expect(collection.maximumRangeDays == 30)
        }
    }

    /// The whole response decodes with collections missing, because a declined
    /// scope means the function returns six of the seven.
    @Test func aPartialResponseDecodesWithTheRestAbsent() throws {
        let payloads = try decode(FitbitPayloads.self, """
        {"sleep":{"sleep":[]},"hrv":null}
        """)
        #expect(payloads.sleep != nil)
        #expect(payloads.hrv == nil)
        #expect(payloads.restingHeartRate == nil)
    }
}
