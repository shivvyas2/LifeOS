import SwiftUI

/// Whoop's recovery bands, using Whoop's own thresholds so the app and the
/// Whoop app never disagree about what a number means.
///
/// The colour is the point. A bare "31%" and a bare "81%" read alike at a
/// glance; red and green do not.
public enum RecoveryBand: Sendable, Equatable, CaseIterable {
    case low        // below 34
    case moderate   // 34 to 66
    case high       // 67 and above

    /// Readings outside the nominal 0 to 100 range still land in a band. Whoop
    /// occasionally reports slightly beyond it and a reading must never fall
    /// through to nothing.
    public static func band(for percentage: Double) -> RecoveryBand {
        switch percentage {
        case ..<34:  .low
        case ..<67:  .moderate
        default:     .high
        }
    }

    public var label: String {
        switch self {
        case .low:      "Low"
        case .moderate: "Moderate"
        case .high:     "High"
        }
    }

    /// Held at the same saturation across the three so none reads as louder
    /// than its neighbour for reasons other than the number.
    public var color: Color {
        switch self {
        case .low:      Color(red: 0.85, green: 0.24, blue: 0.24)
        case .moderate: Color(red: 0.93, green: 0.68, blue: 0.15)
        case .high:     Color(red: 0.20, green: 0.70, blue: 0.42)
        }
    }
}
