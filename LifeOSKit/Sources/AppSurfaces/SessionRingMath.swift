import Foundation

/// How full each ring of the live HUD is, as a fraction of today's ceiling.
///
/// Pure, so the rings on the phone and any later surface agree, and so the
/// arithmetic is tested without a view. A missing reading is an empty ring,
/// never a full one: nothing has been earned yet.
public enum SessionRingMath {
    /// Zones run one to five; with no ceiling for today the top of the scale
    /// is the top zone.
    public static let topZone = 5
    /// The widest target band the ceiling model hands out, so an effort with
    /// no band for today still has a scale to sit on.
    public static let topEffort = 18.0

    public static func heartFill(zone: Int?, ceilingMaxZone: Int?) -> Double {
        guard let zone else { return 0 }
        let top = max(ceilingMaxZone ?? topZone, 1)
        return clamp(Double(zone) / Double(top))
    }

    public static func effortFill(effort: Double?, target: ClosedRange<Double>?) -> Double {
        guard let effort else { return 0 }
        let top = max(target?.upperBound ?? topEffort, 0.1)
        return clamp(effort / top)
    }

    /// Past the band, not merely at its top: the ring is full at the top and
    /// only turns red once the person has gone beyond it.
    public static func effortIsOver(effort: Double?, target: ClosedRange<Double>?) -> Bool {
        guard let effort, let target else { return false }
        return effort > target.upperBound
    }

    public static func batteryFill(percent: Int?) -> Double {
        guard let percent else { return 0 }
        return clamp(Double(percent) / 100)
    }

    /// Seconds per beat, for the pulse. Nil when there is nothing to pulse to.
    public static func beatPeriod(bpm: Int?) -> Double? {
        guard let bpm, bpm > 0 else { return nil }
        return 60 / Double(bpm)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
