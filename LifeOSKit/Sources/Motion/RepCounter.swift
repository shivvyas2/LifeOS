import Foundation

/// Counts repetitions from wrist acceleration. Pure: samples in, a count
/// out, so it is tested on synthetic signals and tuned from hardware later.
///
/// Each axis is smoothed twice: a fast average follows the movement, a slow
/// one follows posture and gravity drift, and the difference is projected
/// onto the direction of the first lift, so a rep is a signed swing, not a
/// rectified bump. A lift is a swing that is still growing when it passes the
/// threshold, so the axis locks to the leading edge of a movement rather than
/// the tail of one already half spent. A rep is a rise above the threshold
/// followed by a fall below its negative, the half cycle between them taking
/// between half of `minPeriod` and half of `maxPeriod` seconds. Nothing counts
/// while settling after `reset()`, and each rep starts a refractory window of
/// half of `minPeriod`.
public struct RepCounter: Sendable {
    public struct Sample: Sendable {
        public var t: TimeInterval
        public var x: Double
        public var y: Double
        public var z: Double
        public init(t: TimeInterval, x: Double, y: Double, z: Double) { self.t = t; self.x = x; self.y = y; self.z = z }
    }
    private struct Vec: Sendable { var x = 0.0, y = 0.0, z = 0.0 }

    public let settleSeconds: Double
    public let minPeriod: Double
    public let maxPeriod: Double
    public let threshold: Double
    public private(set) var reps: Int = 0

    private let fastTau = 0.15
    private let slowTau = 2.0
    private var fast: Vec?
    private var slow: Vec?
    private var axis: Vec?
    private var lastT: TimeInterval?
    private var startT: TimeInterval?
    private var riseT: TimeInterval?
    private var refractoryUntil: TimeInterval = -.infinity
    private var lastMagnitude: Double?

    public init(settleSeconds: Double = 1.0, minPeriod: Double = 0.6, maxPeriod: Double = 4.0, threshold: Double = 0.15) {
        self.settleSeconds = settleSeconds; self.minPeriod = minPeriod; self.maxPeriod = maxPeriod; self.threshold = threshold
    }

    public mutating func reset() {
        reps = 0; fast = nil; slow = nil; axis = nil; lastT = nil; startT = nil; riseT = nil
        refractoryUntil = -.infinity; lastMagnitude = nil
    }

    /// Feed one sample; returns true when this sample completed a rep.
    public mutating func add(_ sample: Sample) -> Bool {
        let value = Vec(x: sample.x, y: sample.y, z: sample.z)
        let dt = lastT.map { max(0.001, sample.t - $0) } ?? 0.02
        lastT = sample.t
        if startT == nil { startT = sample.t }
        fast = smooth(fast, toward: value, dt: dt, tau: fastTau)
        slow = smooth(slow, toward: value, dt: dt, tau: slowTau)
        guard let fast, let slow, let startT else { return false }
        let d = Vec(x: fast.x - slow.x, y: fast.y - slow.y, z: fast.z - slow.z)
        let magnitude = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        // Tracked for every sample, so the first sample past settling still
        // knows whether the swing it lands on is growing or already fading.
        let rising = lastMagnitude.map { magnitude > $0 } ?? false
        lastMagnitude = magnitude
        guard sample.t - startT >= settleSeconds, sample.t >= refractoryUntil else { return false }
        if axis == nil {
            // The first lift above the threshold fixes the direction for this
            // set. It has to still be growing, or settling can end mid fall and
            // lock the axis backwards, spending the first cycle on a half swing.
            guard magnitude > threshold, rising else { return false }
            axis = Vec(x: d.x / magnitude, y: d.y / magnitude, z: d.z / magnitude)
        }
        guard let axis else { return false }
        let s = d.x * axis.x + d.y * axis.y + d.z * axis.z
        if riseT == nil {
            if s > threshold { riseT = sample.t }
            return false
        }
        guard s < -threshold, let rise = riseT else { return false }
        riseT = nil
        let half = sample.t - rise
        guard half >= minPeriod / 2, half <= maxPeriod / 2 else { return false }
        reps += 1
        refractoryUntil = sample.t + minPeriod / 2
        return true
    }

    private func smooth(_ current: Vec?, toward value: Vec, dt: Double, tau: Double) -> Vec {
        guard let current else { return value }
        let alpha = 1 - exp(-dt / tau)
        return Vec(x: current.x + alpha * (value.x - current.x), y: current.y + alpha * (value.y - current.y), z: current.z + alpha * (value.z - current.z))
    }
}
