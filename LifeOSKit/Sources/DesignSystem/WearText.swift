import Foundation

/// What to wear, from the day's numbers. A rule table, not a model: the
/// same forecast always gives the same line, and the line is tested.
public enum WearText {
    /// The first waking hour whose rain chance is 0.4 or more, or nil.
    public static func firstWetHour(_ rainChanceByHour: [Double], wakingHours: Range<Int> = 7..<22) -> Int? {
        wakingHours.first { hour in hour < rainChanceByHour.count && rainChanceByHour[hour] >= 0.4 }
    }

    /// `currentHour` is the hour now when the line is for today, so rain
    /// already falling is not announced as ahead; nil on any other day.
    public static func line(
        feelsLikeHighC high: Double, feelsLikeLowC low: Double, rainChanceByHour rain: [Double],
        windKph wind: Double, uvIndex uv: Int, wakingHours: Range<Int> = 7..<22,
        currentHour: Int? = nil, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        var parts: [String] = []
        switch high {
        case ..<5: parts.append("coat, hat and gloves")
        case ..<12: parts.append("a warm jacket")
        case ..<18: parts.append("a light jacket or a sweater")
        case ..<25: parts.append("a t-shirt")
        default: parts.append("light clothes, and carry water")
        }
        if high >= 12, high - low > 10 { parts.append("layers for the morning") }
        if let wet = firstWetHour(rain, wakingHours: wakingHours) {
            let threshold = currentHour ?? wakingHours.lowerBound
            if wet > threshold {
                parts.append("an umbrella after \(hourText(wet, calendar: calendar, locale: locale))")
            } else {
                parts.append("an umbrella")
            }
        }
        if wind >= 30 { parts.append("a windproof layer") }
        if uv >= 6 { parts.append("sunscreen") }
        let joined = parts.joined(separator: ", ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    /// `15:00` or `3:00 pm`, the way the device shows a time.
    public static func hourText(_ hour: Int, calendar: Calendar, locale: Locale) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let reference = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: .now)) ?? .now
        return reference.formatted(style.hour().minute())
    }
}

/// The one line under the day's masthead: the weather in plain words, what
/// is on, what is due. Nothing is known: no line.
public enum DayLookText {
    public struct Weather: Equatable, Sendable {
        public let conditionSymbol: String
        public let feelsLikeHighC: Double
        public let rainChanceByHour: [Double]
        public init(conditionSymbol: String, feelsLikeHighC: Double, rainChanceByHour: [Double]) {
            self.conditionSymbol = conditionSymbol; self.feelsLikeHighC = feelsLikeHighC; self.rainChanceByHour = rainChanceByHour
        }
    }

    public static func sentence(
        weather: Weather?, agendaCount: Int, firstStart: Date?, dueCount: Int,
        currentHour: Int? = nil, wakingHours: Range<Int> = 7..<22,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        if weather == nil, agendaCount == 0, dueCount == 0 { return nil }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        var sentences: [String] = []
        if let weather {
            var clause = "\(band(weather.feelsLikeHighC)) and \(condition(weather.conditionSymbol))"
            if let wet = WearText.firstWetHour(weather.rainChanceByHour, wakingHours: wakingHours),
               wet > (currentHour ?? wakingHours.lowerBound) {
                clause += ", rain from \(WearText.hourText(wet, calendar: calendar, locale: locale))"
            }
            sentences.append(clause + ".")
        }
        var dayClause: String
        switch agendaCount {
        case 0: dayClause = "Nothing on"
        case 1: dayClause = "One thing on" + (firstStart.map { " at \($0.formatted(style.hour().minute()))" } ?? "")
        default: dayClause = "\(count(agendaCount, capitalised: true)) things on" + (firstStart.map { ", first at \($0.formatted(style.hour().minute()))" } ?? "")
        }
        if dueCount > 0 {
            dayClause += ", \(count(dueCount, capitalised: false)) \(dueCount == 1 ? "task" : "tasks") due"
        }
        sentences.append(dayClause + ".")
        return sentences.joined(separator: " ")
    }

    private static func band(_ high: Double) -> String {
        switch high {
        case ..<5: "Cold"
        case ..<12: "Cool"
        case ..<18: "Mild"
        case ..<25: "Warm"
        default: "Hot"
        }
    }

    /// From the SF Symbol WeatherKit names the condition with.
    private static func condition(_ symbol: String) -> String {
        let s = symbol.lowercased()
        if s.contains("rain") || s.contains("drizzle") { return "wet" }
        if s.contains("snow") || s.contains("sleet") || s.contains("hail") { return "snowy" }
        if s.contains("wind") { return "windy" }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") { return "foggy" }
        if s.contains("cloud") { return "cloudy" }
        if s.contains("sun") { return "sunny" }
        return "clear"
    }

    private static func count(_ n: Int, capitalised: Bool) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let word = n < words.count ? words[n] : "\(n)"
        return capitalised ? word.prefix(1).uppercased() + word.dropFirst() : word
    }
}
