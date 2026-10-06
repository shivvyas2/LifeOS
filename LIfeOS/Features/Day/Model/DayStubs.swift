#if DEBUG
import Foundation
import CoreLocation
import AppSurfaces

/// A fixed forecast for previews: mild, cloudy, rain from three.
struct StubWeatherProvider: WeatherProviding {
    var forecast: DayForecast?

    static func sample(for day: Date, calendar: Calendar = .current) -> DayForecast {
        var rain = Array(repeating: 0.1, count: 24)
        for hour in 15...17 { rain[hour] = 0.55 }
        let start = calendar.startOfDay(for: day)
        return DayForecast(day: start, conditionSymbol: "cloud.sun", conditionName: "Partly cloudy",
                           highC: 18, lowC: 9, feelsLikeHighC: 17, feelsLikeLowC: 8,
                           rainChanceByHour: rain, windKph: 12, uvIndex: 3,
                           sunrise: calendar.date(bySettingHour: 7, minute: 12, second: 0, of: start),
                           sunset: calendar.date(bySettingHour: 18, minute: 31, second: 0, of: start),
                           fetchedAt: .now)
    }

    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast? {
        forecast ?? Self.sample(for: day)
    }
}

/// A location that answers at once with whatever access the page wants.
@MainActor
final class StubLocation: LocationProviding {
    private(set) var access: LocationAccess
    init(access: LocationAccess = .granted) { self.access = access }
    func requestAccess() async -> LocationAccess {
        if access == .notDetermined { access = .granted }
        return access
    }
    func currentLocation() async throws -> CLLocation { CLLocation(latitude: 51.5, longitude: -0.12) }
}
#endif
