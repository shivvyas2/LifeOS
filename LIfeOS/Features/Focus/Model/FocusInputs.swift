import Foundation
import SwiftData
import CoreLocation
import Persistence
import AppSurfaces
import Soundscape

/// What the soundscape reads from the day, gathered once at the start.
struct FocusInputs {
    var weather: WeatherInput?
    var recovery: RecoveryLevel?
    var restingHeartRate: Double?

    static func gather(context: ModelContext, providers: DayProviders?) async -> FocusInputs {
        var inputs = FocusInputs()
        let today = Calendar.current.startOfDay(for: .now)
        if let metrics = try? MetricsStore(context: context, calendar: .current).metrics(from: today, to: today).first {
            inputs.recovery = metrics.whoopRecoveryPct.map(RecoveryLevel.init(percentage:))
            inputs.restingHeartRate = metrics.restingHR
        }
        // Weather only when location is already allowed, and only if it comes
        // back within five seconds; the session never waits longer than that.
        if let providers, providers.location.access == .granted {
            let location = providers.location, weather = providers.weather
            inputs.weather = await firstValue(within: .seconds(5)) { @MainActor in
                guard let here = try? await location.currentLocation(),
                      let forecast = try? await weather.forecast(for: .now, at: here) else { return nil }
                let hour = Calendar.current.component(.hour, from: .now)
                let chance = forecast.rainChanceByHour.indices.contains(hour) ? forecast.rainChanceByHour[hour] : nil
                return WeatherInput(symbol: forecast.conditionSymbol, windKph: forecast.windKph, rainChanceNow: chance)
            }
        }
        return inputs
    }
}
