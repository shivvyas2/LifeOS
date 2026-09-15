import WatchKit
import HealthKit

/// The phone starts a workout here: watchOS launches the app and hands the
/// configuration to this delegate. `WKApplicationDelegate` is `NS_SWIFT_UI_ACTOR`,
/// so the whole class is main-actor isolated and the two statics are safe
/// mutable state rather than globals needing `nonisolated(unsafe)`.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Set when the configuration arrives before the app's `.task` runs.
    static var pendingConfiguration: HKWorkoutConfiguration?
    /// Set by the app's `.task`; called on the main actor from `handle(_:)`.
    static var onConfiguration: ((HKWorkoutConfiguration) -> Void)?
    /// Set when watchOS relaunches the app over a session that is still
    /// active in HealthKit, before the app's `.task` runs.
    static var pendingRecovery = false
    /// Set by the app's `.task`; called on the main actor from
    /// `handleActiveWorkoutRecovery()`.
    static var onRecovery: (() -> Void)?

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        if let handler = Self.onConfiguration { handler(workoutConfiguration) }
        else { Self.pendingConfiguration = workoutConfiguration }
    }

    /// watchOS calls this instead of `handle(_:)` when the app is relaunched
    /// with a HealthKit workout session still active, e.g. after the system
    /// killed the app mid-workout. Routes to the controller's `recover()`
    /// the same way `handle(_:)` routes a fresh configuration to `start(_:)`.
    func handleActiveWorkoutRecovery() {
        if let handler = Self.onRecovery { handler() }
        else { Self.pendingRecovery = true }
    }
}
