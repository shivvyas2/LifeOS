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
