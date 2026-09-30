import Foundation
import AppSurfaces

/// Experimental threshold detector, not a trained stroke/technique classifier.
/// Detects bursts of wrist rotation with acceleration, then waits for the
/// follow-through to settle. Accuracy requires labeled on-court validation.
public struct BadmintonSwingDetector: Sendable {
    public struct Sample: Sendable {
        public var time: Double
        public var acceleration: Double
        public var rotation: Double
        public var frame: WristFrame
        public init(time: Double, acceleration: Double, rotation: Double, frame: WristFrame) {
            self.time = time; self.acceleration = acceleration; self.rotation = rotation; self.frame = frame
        }
    }
    public private(set) var analysis: SwingAnalysis
    private var previous: Double?
    private var settlingUntil: Double?
    private var began: Double?
    private var quietSince: Double?
    private var peakRotation = 0.0
    private var peakAcceleration = 0.0
    private var frames: [WristFrame] = []
    private var refractoryUntil = -1.0
    public init(profile: ActivityAthleteProfile? = nil, restoring: SwingAnalysis? = nil) {
        analysis = restoring ?? SwingAnalysis(profile: profile)
    }
    /// Pauses and gaps never join two separate motions into a swing.
    public mutating func interrupt() {
        previous = nil; settlingUntil = nil; began = nil; quietSince = nil; frames = []
    }
    @discardableResult public mutating func add(_ s: Sample) -> Bool {
        guard s.time.isFinite, s.time >= 0, s.acceleration.isFinite, s.rotation.isFinite,
              (0...100).contains(s.acceleration), (0...100).contains(s.rotation), s.frame.isValid else { interrupt(); analysis.interrupted = true; return false }
        if let previous, s.time <= previous { return false }
        if let previous, s.time - previous > 0.2 { interrupt(); analysis.interrupted = true }
        if let previous { analysis.sampledSeconds += s.time - previous }
        previous = s.time
        if settlingUntil == nil { settlingUntil = s.time + 1 }
        guard s.time >= settlingUntil!, s.time >= refractoryUntil else { return false }
        if began == nil {
            guard s.rotation >= 4.5, s.acceleration >= 0.65 else { return false }
            began = s.time; peakRotation = 0; peakAcceleration = 0; frames = []
        }
        guard let began else { return false }
        peakRotation = max(peakRotation, s.rotation); peakAcceleration = max(peakAcceleration, s.acceleration)
        var frame = s.frame; frame.t = s.time - began
        if frames.count < 8, frames.last.map({ frame.t - $0.t >= 0.12 }) ?? true { frames.append(frame) }
        if s.rotation < 2 { if quietSince == nil { quietSince = s.time } } else { quietSince = nil }
        let duration = s.time - began
        let timedOut = duration > 1.6
        guard timedOut || quietSince.map({ s.time - $0 >= 0.1 }) == true else { return false }
        self.began = nil; quietSince = nil; refractoryUntil = s.time + 0.25
        guard !timedOut, duration >= 0.08, peakAcceleration >= 1.0 else { return false }
        guard analysis.events.count < SwingAnalysis.eventLimit else { analysis.truncated = true; return false }
        analysis.events.append(SwingEvent(id: analysis.events.count, time: began, duration: duration,
                                         peakRotation: peakRotation, peakAcceleration: peakAcceleration, frames: frames))
        return true
    }
}
