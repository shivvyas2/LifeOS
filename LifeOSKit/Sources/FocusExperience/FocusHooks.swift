#if os(iOS)
import Foundation
import SwiftData

/// What a focus session needs from the app running it. LifeOS gathers its
/// inputs from WHOOP and its weather provider and has a watch for heart
/// rate; LifeOS Focus has neither yet. Each app also syncs its own way.
public struct FocusHooks {
    public var gatherInputs: @MainActor (ModelContext) async -> FocusInputs
    public var sessionSaved: @MainActor () -> Void
    public var heartRate: (any FocusHeartRateSource)?

    public init(gatherInputs: @escaping @MainActor (ModelContext) async -> FocusInputs,
                sessionSaved: @escaping @MainActor () -> Void,
                heartRate: (any FocusHeartRateSource)?) {
        self.gatherInputs = gatherInputs
        self.sessionSaved = sessionSaved
        self.heartRate = heartRate
    }

    @MainActor public static let none = FocusHooks(gatherInputs: { _ in FocusInputs() }, sessionSaved: {}, heartRate: nil)
}

/// A live heart rate during a session (LifeOS: the paired watch).
@MainActor
public protocol FocusHeartRateSource: AnyObject {
    var onHeartRate: ((Int) -> Void)? { get set }
    func start() async
    func stop()
}
#endif
