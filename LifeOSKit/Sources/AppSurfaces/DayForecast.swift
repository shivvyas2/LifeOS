import Foundation

/// One day's weather as the day screen draws it, in Celsius and km/h so the
/// rules in DesignSystem read plain numbers; the screen formats for the
/// device. Shared through AppSurfaces so a widget can read it later.
public struct DayForecast: Codable, Equatable, Sendable {
    public let day: Date
    public let conditionSymbol: String
    public let conditionName: String
    public let highC: Double
    public let lowC: Double
    public let feelsLikeHighC: Double
    public let feelsLikeLowC: Double
    /// 24 values, 0 to 1, from the day's first hour.
    public let rainChanceByHour: [Double]
    public let windKph: Double
    public let uvIndex: Int
    public let sunrise: Date?
    public let sunset: Date?
    public let fetchedAt: Date

    public init(day: Date, conditionSymbol: String, conditionName: String,
                highC: Double, lowC: Double, feelsLikeHighC: Double, feelsLikeLowC: Double,
                rainChanceByHour: [Double], windKph: Double, uvIndex: Int,
                sunrise: Date?, sunset: Date?, fetchedAt: Date) {
        self.day = day; self.conditionSymbol = conditionSymbol; self.conditionName = conditionName
        self.highC = highC; self.lowC = lowC; self.feelsLikeHighC = feelsLikeHighC; self.feelsLikeLowC = feelsLikeLowC
        self.rainChanceByHour = rainChanceByHour; self.windKph = windKph; self.uvIndex = uvIndex
        self.sunrise = sunrise; self.sunset = sunset; self.fetchedAt = fetchedAt
    }

    /// Fresh for an hour: a forecast changes slower than a person reopens a day.
    public func isFresh(at now: Date, within interval: TimeInterval = 3_600) -> Bool {
        now.timeIntervalSince(fetchedAt) < interval
    }
}
