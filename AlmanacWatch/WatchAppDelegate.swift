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

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        if let handler = Self.onConfiguration { handler(workoutConfiguration) }
        else { Self.pendingConfiguration = workoutConfiguration }
    }
}
