import Foundation

/// The one place a reading becomes text, so the HUD, the tiles and any
/// later surface agree on rounding and on the dash that means "no reading".
public extension LiveSessionReadout {
    static let missing = "\u{2014}"
    var heartRateText: String? { heartRate.map(String.init) }
    var zoneText: String? { zone.map { "Z\($0)" } }
    var effortText: String? { effort.map { String(format: "%.1f", $0) } }
    var caloriesText: String? { calories.map(String.init) }
    var distanceKilometresText: String? { distanceMeters.map { String(format: "%.2f", Double($0) / 1000) } }
    var batteryText: String? { batteryPercent.map { "\($0)%" } }
    var repsText: String? { reps.map(String.init) }
    var setText: String? { setIndex.map { "Set \($0)" } }
    /// "WHOOP recovery", "Apple Health", or "Battery unknown".
    var capacitySourceName: String {
        switch capacitySource {
        case "whoop": "WHOOP recovery"
        case "health": "Apple Health"
        default: "Battery unknown"
        }
    }
}
