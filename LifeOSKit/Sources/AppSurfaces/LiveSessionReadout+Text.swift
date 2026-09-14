import Foundation

/// The one place a reading becomes text, so the HUD, the tiles and any
/// later surface agree on rounding and on the dash that means "no reading".
public extension LiveSessionReadout {
    static let missing = "\u{2014}"
    var heartRateText: String { heartRate.map(String.init) ?? Self.missing }
    var zoneText: String? { zone.map { "Z\($0)" } }
    var effortText: String { effort.map { String(format: "%.1f", $0) } ?? Self.missing }
    var caloriesText: String { calories.map(String.init) ?? Self.missing }
    var distanceKilometresText: String { distanceMeters.map { String(format: "%.2f", Double($0) / 1000) } ?? Self.missing }
    var batteryText: String { batteryPercent.map { "\($0)%" } ?? Self.missing }
    /// "WHOOP recovery", "Apple Health", or "Battery unknown".
    var capacitySourceName: String {
        switch capacitySource {
        case "whoop": "WHOOP recovery"
        case "health": "Apple Health"
        default: "Battery unknown"
        }
    }
}
