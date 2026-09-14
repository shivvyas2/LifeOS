import Foundation
import AppSurfaces

/// Heart-rate zones from age. Tanaka's estimate of maximum heart rate and
/// WHOOP's zone bands, so the number on the HUD agrees with the number in
/// the app the person already trusts.
///
/// No birth date means no zones, never a guessed maximum: a zone built on an
/// assumed age would be a reading the person never gave.
public struct HeartRateZones: Equatable, Sendable {
    public let maxHeartRate: Int

    public init?(birthDate: Date?, on date: Date = .now, calendar: Calendar = .current) {
        guard let birthDate,
              let age = calendar.dateComponents([.year], from: birthDate, to: date).year,
              (10...120).contains(age) else { return nil }
        maxHeartRate = Int((208.0 - 0.7 * Double(age)).rounded())
    }

    /// 0 below half of maximum, then one zone per ten percent up to 5.
    public func zone(for bpm: Int) -> Int {
        let fraction = Double(bpm) / Double(maxHeartRate)
        switch fraction {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }
}

/// Estimated effort on WHOOP's 0 to 21 scale.
///
/// Seconds in each zone add a weight to a running load, and the load maps
/// through a saturating curve so a long day approaches 21 without reaching
/// it. The constants are pinned by calibration tests: a steady hour in zone 3
/// is about 12, a hard ninety minutes about 18. Retuning is a deliberate
/// change with a diff, not a drift.
public struct EffortAccumulator: Codable, Equatable, Sendable {
    public static let weights: [Double] = [0, 0.15, 0.28, 0.35, 0.45, 0.63]
    public static let scale = 1500.0
    /// A gap in the stream is not effort that was measured. One reading
    /// credits at most this many seconds.
    public static let maxCredit: TimeInterval = 5

    public private(set) var load: Double

    public init(load: Double = 0) { self.load = max(0, load) }

    public mutating func add(zone: Int, seconds: TimeInterval) {
        guard seconds > 0, Self.weights.indices.contains(zone) else { return }
        load += Self.weights[zone] * seconds
    }

    public var effort: Double { 21 * (1 - exp(-load / Self.scale)) }

    /// Seconds to credit a reading at `date` given the previous reading.
    public static func credit(previous: Date?, at date: Date) -> TimeInterval {
        guard let previous else { return 0 }
        return min(maxCredit, max(0, date.timeIntervalSince(previous)))
    }
}
