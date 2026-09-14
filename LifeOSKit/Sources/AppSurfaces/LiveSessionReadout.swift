import Foundation

/// How hard the person is going against today's ceiling. Drives colour and
/// the headline on every surface; the words live here so they never drift.
public enum PushState: String, Codable, Hashable, Sendable {
    case easy, onTrack, nearLimit, overLimit

    public var headline: String {
        switch self {
        case .easy: "Easy going"
        case .onTrack: "On track"
        case .nearLimit: "Near your limit"
        case .overLimit: "Over your target"
        }
    }
}

/// The one value every live surface renders: the in-app HUD, the lock screen
/// and the Dynamic Island. Every reading is optional because a missing
/// sensor is not a zero. `elapsed` is the accumulated time while running or
/// paused; `runningSince` is nil while paused, which is how a surface knows.
public struct LiveSessionReadout: Codable, Hashable, Sendable {
    public var elapsed: TimeInterval
    public var runningSince: Date?
    public var heartRate: Int?
    public var zone: Int?
    /// Estimated, on WHOOP's 0 to 21 scale, rounded to a tenth before publishing.
    public var effort: Double?
    public var calories: Int?
    public var distanceMeters: Int?
    public var batteryPercent: Int?
    /// "whoop" or "health", for the eyebrow that says where the battery came from.
    public var capacitySource: String?
    public var ceilingMaxZone: Int?
    public var ceilingTarget: ClosedRange<Double>?
    public var push: PushState

    public init(elapsed: TimeInterval, runningSince: Date?, push: PushState) {
        self.elapsed = elapsed
        self.runningSince = runningSince
        self.push = push
    }

    /// Anchor for `Text(timerInterval:)`, so the system ticks the timer
    /// without an update per second.
    public var timerAnchor: Date? { runningSince?.addingTimeInterval(-elapsed) }
    public var isPaused: Bool { runningSince == nil }
}
