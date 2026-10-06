import Foundation
import WeatherKit
import CoreLocation
import AppSurfaces

/// WeatherKit's day and hours, folded into one `DayForecast`. Feels-like
/// high and low come from the hours, which is what a person dressing at
/// seven and walking home at six actually meets.
struct WeatherKitProvider: WeatherProviding {
    private let calendar = Calendar.current

    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let (daily, hourly) = try await WeatherService.shared.weather(
            for: location,
            including: .daily(startDate: start, endDate: end), .hourly(startDate: start, endDate: end)
        )
        guard let dayWeather = daily.forecast.first(where: { calendar.isDate($0.date, inSameDayAs: start) }) else { return nil }
        let hours = hourly.forecast.filter { $0.date >= start && $0.date < end }
        var rain = Array(repeating: 0.0, count: 24)
        for hour in hours {
            rain[calendar.component(.hour, from: hour.date)] = hour.precipitationChance
        }
        let feels = hours.map { $0.apparentTemperature.converted(to: .celsius).value }
        let high = dayWeather.highTemperature.converted(to: .celsius).value
        let low = dayWeather.lowTemperature.converted(to: .celsius).value
        return DayForecast(
            day: start,
            conditionSymbol: dayWeather.symbolName,
            conditionName: dayWeather.condition.description,
            highC: high, lowC: low,
            feelsLikeHighC: feels.max() ?? high, feelsLikeLowC: feels.min() ?? low,
            rainChanceByHour: rain,
            windKph: dayWeather.wind.speed.converted(to: .kilometersPerHour).value,
            uvIndex: dayWeather.uvIndex.value,
            sunrise: dayWeather.sun.sunrise, sunset: dayWeather.sun.sunset,
            fetchedAt: .now
        )
    }
}
