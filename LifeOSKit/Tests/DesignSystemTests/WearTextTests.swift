import Testing
import Foundation
@testable import DesignSystem

@Suite struct WearTextTests {
    private let gb = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func rain(at hours: Int...) -> [Double] {
        var r = Array(repeating: 0.1, count: 24)
        for h in hours { r[h] = 0.6 }
        return r
    }
    private func line(high: Double, low: Double = 8, rain: [Double] = Array(repeating: 0, count: 24),
                      wind: Double = 10, uv: Int = 2, currentHour: Int? = nil) -> String {
        WearText.line(feelsLikeHighC: high, feelsLikeLowC: low, rainChanceByHour: rain, windKph: wind, uvIndex: uv,
                      currentHour: currentHour, calendar: calendar, locale: gb)
    }

    @Test func theBandsAndThePinnedExamples() {
        #expect(line(high: 15, low: 10, rain: rain(at: 15)) == "A light jacket or a sweater, an umbrella after 15:00.")
        #expect(line(high: 2, low: -3, wind: 35) == "Coat, hat and gloves, a windproof layer.")
        #expect(line(high: 20, low: 14, uv: 7) == "A t-shirt, sunscreen.")
        #expect(line(high: 28, low: 20, uv: 8) == "Light clothes, and carry water, sunscreen.")
        #expect(line(high: 8, low: 4) == "A warm jacket.")
    }

    @Test func layersWhenTheMorningIsMuchColder() {
        #expect(line(high: 22, low: 9) == "A t-shirt, layers for the morning.")
        #expect(line(high: 10, low: -2) == "A warm jacket.")
    }

    @Test func umbrellaNamesTheHourOnlyWhenAhead() {
        #expect(line(high: 15, low: 12, rain: rain(at: 15), currentHour: 9) == "A light jacket or a sweater, an umbrella after 15:00.")
        #expect(line(high: 15, low: 12, rain: rain(at: 15), currentHour: 16) == "A light jacket or a sweater, an umbrella.")
        #expect(line(high: 15, low: 12, rain: rain(at: 7)) == "A light jacket or a sweater, an umbrella.")
        #expect(line(high: 15, low: 12, rain: rain(at: 3)) == "A light jacket or a sweater.")
    }
}

@Suite struct DayLookTextTests {
    private let gb = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour))!
    }
    private func weather(_ symbol: String, high: Double, wet: Int? = nil) -> DayLookText.Weather {
        var r = Array(repeating: 0.0, count: 24)
        if let wet { r[wet] = 0.7 }
        return DayLookText.Weather(conditionSymbol: symbol, feelsLikeHighC: high, rainChanceByHour: r)
    }

    @Test func everyClausePresent() {
        let s = DayLookText.sentence(weather: weather("sun.max", high: 9, wet: 15), agendaCount: 3, firstStart: at(9),
                                     dueCount: 2, currentHour: 8, calendar: calendar, locale: gb)
        #expect(s == "Cool and sunny, rain from 15:00. Three things on, first at 09:00, two tasks due.")
    }

    @Test func clausesDropOut() {
        #expect(DayLookText.sentence(weather: weather("cloud.rain", high: 3), agendaCount: 0, firstStart: nil, dueCount: 0,
                                     calendar: calendar, locale: gb) == "Cold and wet. Nothing on.")
        #expect(DayLookText.sentence(weather: nil, agendaCount: 1, firstStart: at(14), dueCount: 1,
                                     calendar: calendar, locale: gb) == "One thing on at 14:00, one task due.")
        #expect(DayLookText.sentence(weather: weather("cloud", high: 15), agendaCount: 0, firstStart: nil, dueCount: 1,
                                     calendar: calendar, locale: gb) == "Mild and cloudy. Nothing on, one task due.")
        #expect(DayLookText.sentence(weather: nil, agendaCount: 0, firstStart: nil, dueCount: 0,
                                     calendar: calendar, locale: gb) == nil)
    }

    @Test func rainAlreadyFallingIsNotAnnouncedAsAhead() {
        let s = DayLookText.sentence(weather: weather("cloud.rain", high: 12, wet: 8), agendaCount: 0, firstStart: nil,
                                     dueCount: 0, currentHour: 10, calendar: calendar, locale: gb)
        #expect(s == "Mild and wet. Nothing on.")
    }
}
