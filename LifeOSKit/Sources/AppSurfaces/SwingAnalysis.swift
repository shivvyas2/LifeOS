import Foundation

/// Wrist orientation in Core Motion's arbitrary reference frame. This is not
/// a racket pose, shoulder pose, or position on the court.
public struct WristFrame: Codable, Equatable, Sendable {
    public var t: Double
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double
    public init(t: Double, x: Double, y: Double, z: Double, w: Double) {
        self.t = t; self.x = x; self.y = y; self.z = z; self.w = w
    }
    public var isValid: Bool {
        [t, x, y, z, w].allSatisfy(\.isFinite) && t >= 0
        && (0.9...1.1).contains(x*x + y*y + z*z + w*w)
    }
}
public struct SwingEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    /// Seconds of active workout time, excluding pauses.
    public var time: Double
    public var duration: Double
    public var peakRotation: Double // rad/s, wrist, never racket-head speed
    public var peakAcceleration: Double // g, gravity removed
    public var frames: [WristFrame]
    public init(id: Int, time: Double, duration: Double, peakRotation: Double, peakAcceleration: Double, frames: [WristFrame]) {
        self.id = id; self.time = time; self.duration = duration
        self.peakRotation = peakRotation; self.peakAcceleration = peakAcceleration; self.frames = frames
    }
}
public struct SwingAnalysis: Codable, Equatable, Sendable {
    public var version = 1
    public var sampledSeconds: Double = 0
    public var interrupted = false
    public var truncated = false
    public var events: [SwingEvent] = []
    public var profile: ActivityAthleteProfile?
    public init(profile: ActivityAthleteProfile? = nil) { self.profile = profile }
    /// Keeps the durable WatchConnectivity payload comfortably below its
    /// transfer budget while retaining a useful review window.
    public static let eventLimit = 120
    public var peakRotation: Double? { events.map(\.peakRotation).max() }
    public func isValid(elapsed: Double) -> Bool {
        guard version == 1, sampledSeconds.isFinite, sampledSeconds >= 0, sampledSeconds <= elapsed + 2,
              events.count <= Self.eventLimit, profile?.isValid ?? true else { return false }
        var last = -1.0
        for (index, event) in events.enumerated() {
            guard event.id == index, event.time.isFinite, event.time >= last, event.time <= elapsed + 2,
                  event.duration.isFinite, (0.08...2).contains(event.duration),
                  event.peakRotation.isFinite, (0...100).contains(event.peakRotation),
                  event.peakAcceleration.isFinite, (0...100).contains(event.peakAcceleration),
                  event.frames.count <= 8 else { return false }
            var frameTime = -1.0
            for frame in event.frames {
                guard frame.isValid, frame.t >= frameTime, frame.t <= event.duration + 0.05 else { return false }
                frameTime = frame.t
            }
            last = event.time
        }
        return true
    }
}
