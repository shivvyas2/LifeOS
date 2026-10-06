import Foundation

/// The last forecast per day, in whatever defaults the caller hands it (the
/// app passes the account's). Fresh for an hour; at most fourteen days
/// kept, so flipping through a fortnight costs one call per day, not one
/// per open. Lives beside `DayForecast` so a widget can read the same cache.
public struct WeatherCache {
    private let defaults: UserDefaults
    private static let key = "day.forecasts"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func forecast(for day: Date, calendar: Calendar = .current) -> DayForecast? {
        all()[Self.dayKey(day, calendar: calendar)]
    }

    public func store(_ forecast: DayForecast, calendar: Calendar = .current) {
        var forecasts = all()
        forecasts[Self.dayKey(forecast.day, calendar: calendar)] = forecast
        let kept = forecasts.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(14)
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Drops every stored forecast; the design-preview fixtures use it.
    public func clear() { defaults.removeObject(forKey: Self.key) }

    private func all() -> [String: DayForecast] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: DayForecast].self, from: data) else { return [:] }
        return decoded
    }

    /// `2026-10-06`, the same shape the notification inbox keys its days by.
    public static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: day)
    }
}
