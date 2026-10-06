import Foundation
import CoreLocation

/// Asks for when-in-use access the first time it is needed and returns one
/// reduced-accuracy fix: a city is enough for weather, and nothing here
/// tracks anyone.
@MainActor
final class LocationOnce: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var accessWaiters: [CheckedContinuation<LocationAccess, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var access: LocationAccess { Self.access(for: manager.authorizationStatus) }

    func requestAccess() async -> LocationAccess {
        if access != .notDetermined { return access }
        return await withCheckedContinuation { continuation in
            accessWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> CLLocation {
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -900 { return last }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    private static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .granted
        default: .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let access = Self.access(for: status)
            let waiters = accessWaiters
            accessWaiters = []
            waiters.forEach { $0.resume(returning: access) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume(returning: location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let waiters = locationWaiters
            locationWaiters = []
            waiters.forEach { $0.resume(throwing: error) }
        }
    }
}
