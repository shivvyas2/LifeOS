import Foundation
import Testing
@testable import AppSurfaces

@Suite struct SurfaceRouteTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    @Test func fixedRoutesRoundTripAndRejectAnythingLooser() {
        for route in SurfaceRoute.fixed { #expect(SurfaceRoute(url: route.url) == route) }
        for value in ["https://health", "almanac://health?code=token", "almanac://health/path",
                      "almanac://health#fragment", "almanac://someone@health", "almanac://health:443",
                      "almanac://oauth", "almanac://today?date=2026-10-06"] {
            #expect(SurfaceRoute(url: URL(string: value)!) == nil)
        }
    }

    @Test func aDayLinkCarriesItsDate() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        let route = SurfaceRoute.day(day)
        #expect(route.url.absoluteString == "almanac://day?date=2026-10-06")
        #expect(SurfaceRoute(url: route.url) == .day(day))
        #expect(SurfaceRoute(url: URL(string: "almanac://day?date=2026-10-06T09:00")!) == nil)
        #expect(SurfaceRoute(url: URL(string: "almanac://day?date=not-a-day")!) == nil)
        #expect(SurfaceRoute(url: URL(string: "almanac://day?date=2026-10-06&x=1")!) == nil)
        #expect(SurfaceRoute(url: URL(string: "almanac://day")!) == nil)
    }

    @Test func aForecastRoundTripsAndKnowsWhenItIsStale() throws {
        let now = Date(timeIntervalSince1970: 1_791_900_000)
        let forecast = DayForecast(day: now, conditionSymbol: "cloud.sun", conditionName: "Partly cloudy",
                                   highC: 18, lowC: 9, feelsLikeHighC: 17, feelsLikeLowC: 8,
                                   rainChanceByHour: Array(repeating: 0.1, count: 24), windKph: 12, uvIndex: 3,
                                   sunrise: now, sunset: now.addingTimeInterval(40_000), fetchedAt: now)
        let data = try JSONEncoder().encode(forecast)
        #expect(try JSONDecoder().decode(DayForecast.self, from: data) == forecast)
        #expect(forecast.isFresh(at: now.addingTimeInterval(1_800)))
        #expect(!forecast.isFresh(at: now.addingTimeInterval(3_601)))
    }
}
