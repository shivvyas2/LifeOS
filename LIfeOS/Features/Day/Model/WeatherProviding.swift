import SwiftUI
import CoreLocation
import AppSurfaces
import Integrations

/// Where a day's forecast comes from. WeatherKit in the app, a stub in previews.
protocol WeatherProviding: Sendable {
    func forecast(for day: Date, at location: CLLocation) async throws -> DayForecast?
}

enum LocationAccess: Equatable, Sendable {
    case notDetermined, denied, granted
}

/// One fix, with permission asked on first use rather than at launch.
@MainActor
protocol LocationProviding: AnyObject {
    var access: LocationAccess { get }
    func requestAccess() async -> LocationAccess
    func currentLocation() async throws -> CLLocation
}

/// The day's GitHub card. Nil from `DayProviders` when not connected.
protocol GitHubDayProviding: Sendable {
    /// `force` skips the cache's freshness check, for pull to refresh.
    func project(for day: Date, isToday: Bool, force: Bool) async -> ProjectCardState?
}

/// The providers, handed down the environment so the sheet's calendar and
/// the Today stack push the same day screen with the same sources.
struct DayProviders {
    let weather: any WeatherProviding
    let location: any LocationProviding
    var github: (any GitHubDayProviding)? = nil
}

extension EnvironmentValues {
    @Entry var dayProviders: DayProviders?
}
