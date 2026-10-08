import Foundation

/// Where the session is, as the sound sees it.
public enum SoundPhase: Equatable, Sendable {
    case work
    /// The last minute of a work block; 0 at its start, 1 at the bell.
    case closing(Double)
    case rest
    /// A sleep fade; 0 at its start, 1 at silence.
    case fading(Double)
}

public enum WeatherKind: Equatable, Sendable {
    case clear, rain, snow, other

    /// From a WeatherKit SF Symbol name such as `cloud.drizzle.fill`.
    public init(symbol: String) {
        let s = symbol.lowercased()
        if s.contains("snow") || s.contains("sleet") { self = .snow }
        else if s.contains("rain") || s.contains("drizzle") || s.contains("bolt") { self = .rain }
        else if s.hasPrefix("sun") || s.hasPrefix("moon") { self = .clear }
        else { self = .other }
    }
}

public struct WeatherInput: Equatable, Sendable {
    public var kind: WeatherKind
    public var windKph: Double
    public init(kind: WeatherKind, windKph: Double) { self.kind = kind; self.windKph = windKph }

    /// A day forecast's symbol and wind, plus the chance of rain this hour:
    /// a likely shower counts as rain even under a cloud symbol.
    public init(symbol: String, windKph: Double, rainChanceNow: Double?) {
        var kind = WeatherKind(symbol: symbol)
        if kind != .snow, (rainChanceNow ?? 0) >= 0.6 { kind = .rain }
        self.init(kind: kind, windKph: windKph)
    }
}

/// The same thresholds as the app's `RecoveryBand`.
public enum RecoveryLevel: Equatable, Sendable {
    case low, moderate, high
    public init(percentage: Double) {
        self = percentage < 34 ? .low : percentage < 67 ? .moderate : .high
    }
}

public enum TimeOfDay: Equatable, Sendable {
    case morning, day, evening, night
    public init(hour: Int) {
        switch hour {
        case 5..<11: self = .morning
        case 11..<18: self = .day
        case 18..<22: self = .evening
        default: self = .night
        }
    }
    /// Where in a recipe's tempo range this time sits.
    var tempoPosition: Double {
        switch self { case .morning: 0.75; case .day: 0.5; case .evening: 0.25; case .night: 0 }
    }
}

/// Everything the sound responds to. Missing inputs are nil, never guessed.
public struct Conditions: Equatable, Sendable {
    public var date: Date
    public var timeZone: TimeZone
    public var heartRate: Double?
    public var restingHeartRate: Double?
    public var phase: SoundPhase
    public var weather: WeatherInput?
    public var recovery: RecoveryLevel?
    public var texture: Texture

    public init(date: Date, timeZone: TimeZone = .current, heartRate: Double? = nil, restingHeartRate: Double? = nil,
                phase: SoundPhase = .work, weather: WeatherInput? = nil, recovery: RecoveryLevel? = nil,
                texture: Texture = .auto) {
        self.date = date; self.timeZone = timeZone; self.heartRate = heartRate
        self.restingHeartRate = restingHeartRate; self.phase = phase; self.weather = weather
        self.recovery = recovery; self.texture = texture
    }
}
