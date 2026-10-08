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
            let began = Date.now
            let fetch = Task { @MainActor () -> WeatherInput? in
                guard let location = try? await providers.location.currentLocation(),
                      let forecast = try? await providers.weather.forecast(for: .now, at: location) else { return nil }
                let hour = Calendar.current.component(.hour, from: .now)
                let chance = forecast.rainChanceByHour.indices.contains(hour) ? forecast.rainChanceByHour[hour] : nil
                return WeatherInput(symbol: forecast.conditionSymbol, windKph: forecast.windKph, rainChanceNow: chance)
            }
            let timeout = Task { try? await Task.sleep(for: .seconds(5)); fetch.cancel() }
            let weather = await fetch.value
            timeout.cancel()
            if Date.now.timeIntervalSince(began) <= 5.5 { inputs.weather = weather }
        }
        return inputs
    }
}
