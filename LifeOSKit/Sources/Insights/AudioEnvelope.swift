import Foundation

/// Frame-rate-independent attack/release smoothing for visual audio feedback.
/// This does not affect speech detection or the captured audio.
public struct AudioEnvelope: Sendable {
    public private(set) var value: Double = 0
    public init() {}

    @discardableResult
    public mutating func update(target: Double, elapsed: Double) -> Double {
        let target = target.isFinite ? min(max(target, 0), 1) : 0
        let elapsed = elapsed.isFinite ? min(max(elapsed, 0), 1) : 0
        let timeConstant = target > value ? 0.075 : 0.28
        value += (target - value) * (1 - exp(-elapsed / timeConstant))
        return value
    }

    public static func level(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max((decibels + 50) / 42, 0), 1)
    }
}
