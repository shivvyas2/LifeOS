import Foundation
import Testing
@testable import AppSurfaces

@Suite struct WeatherCacheTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func forecast(day: Date, fetchedAt: Date) -> DayForecast {
        DayForecast(day: day, conditionSymbol: "cloud.sun", conditionName: "Partly cloudy",
                    highC: 18, lowC: 9, feelsLikeHighC: 17, feelsLikeLowC: 8,
                    rainChanceByHour: Array(repeating: 0, count: 24), windKph: 12, uvIndex: 3,
                    sunrise: nil, sunset: nil, fetchedAt: fetchedAt)
    }

    private func scratchDefaults() -> (UserDefaults, String) {
        let name = "WeatherCacheTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func aDayIsKeyedByItsCalendarDate() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9))!
        #expect(WeatherCache.dayKey(day, calendar: calendar) == "2026-10-06")
    }

    @Test func aStoredForecastComesBackForItsDayOnlyUntilCleared() {
        let (defaults, name) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = WeatherCache(defaults: defaults)
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        let stored = forecast(day: day, fetchedAt: day)
        cache.store(stored, calendar: calendar)
        #expect(cache.forecast(for: day.addingTimeInterval(3_600 * 20), calendar: calendar) == stored)
        #expect(cache.forecast(for: day.addingTimeInterval(86_400), calendar: calendar) == nil)
        cache.clear()
        #expect(cache.forecast(for: day, calendar: calendar) == nil)
    }

    @Test func onlyTheNewestFourteenAreKept() {
        let (defaults, name) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let cache = WeatherCache(defaults: defaults)
        let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        for offset in 0..<16 {
            let day = first.addingTimeInterval(Double(offset) * 86_400)
            cache.store(forecast(day: day, fetchedAt: day), calendar: calendar)
        }
        #expect(cache.forecast(for: first, calendar: calendar) == nil)
        #expect(cache.forecast(for: first.addingTimeInterval(86_400), calendar: calendar) == nil)
        #expect(cache.forecast(for: first.addingTimeInterval(2 * 86_400), calendar: calendar) != nil)
        #expect(cache.forecast(for: first.addingTimeInterval(15 * 86_400), calendar: calendar) != nil)
    }
}
