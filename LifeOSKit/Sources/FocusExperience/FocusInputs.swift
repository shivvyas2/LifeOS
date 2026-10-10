#if os(iOS)
import Soundscape

/// What the soundscape is composed from besides the mood. Any of it may be
/// missing; the composer works without it.
public struct FocusInputs {
    public var weather: WeatherInput?
    public var recovery: RecoveryLevel?
    public var restingHeartRate: Double?

    public init(weather: WeatherInput? = nil, recovery: RecoveryLevel? = nil, restingHeartRate: Double? = nil) {
        self.weather = weather; self.recovery = recovery; self.restingHeartRate = restingHeartRate
    }
}
#endif
